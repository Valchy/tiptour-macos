import Foundation

// MARK: - Route

/// Which service carries JEV decisions. The single JEV key field accepts either
/// a TypeSafe key, a Vercel AI Gateway key or an OpenRouter key, and the key
/// itself picks the route: Vercel AI Gateway keys start with "vck_",
/// OpenRouter keys with "sk-or-".
nonisolated enum JevRoute: Equatable {
    case typeSafeDirect
    case vercelAIGateway
    case openRouter

    static let vercelAIGatewayKeyPrefix = "vck_"
    static let openRouterKeyPrefix = "sk-or-"

    init(apiKey: String) {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAPIKey.hasPrefix(Self.vercelAIGatewayKeyPrefix) {
            self = .vercelAIGateway
        } else if trimmedAPIKey.hasPrefix(Self.openRouterKeyPrefix) {
            self = .openRouter
        } else {
            self = .typeSafeDirect
        }
    }

    var displayName: String {
        switch self {
        case .typeSafeDirect: return "TypeSafe direct"
        case .vercelAIGateway: return "Vercel AI Gateway"
        case .openRouter: return "OpenRouter"
        }
    }
}

// MARK: - Vercel AI Gateway transport

/// Sends Jev questions through Vercel AI Gateway's evaluation-model endpoint,
/// the same wire format the AI SDK's `experimental_evaluate` uses
/// (@ai-sdk/gateway 4.x, model "typesafe-ai/jev").
///
/// The gateway speaks the AI SDK evaluation spec rather than TypeSafe's native
/// one. Choice questions are the known-good path through its TypeSafe provider
/// (TipTour's requests with boolean questions got 503s while a plain choice
/// worked), so a TypeSafe "noul" question goes out as
/// a two-option choice (yes / no) and P(yes) is read back as the noul value.
/// Usage is camelCase. Everything is mapped back into `JevResponse` so
/// `JevGrounding.decision` validates both routes identically.
nonisolated enum JevVercelGateway {
    static let endpoint = URL(string: "https://ai-gateway.vercel.sh/v4/ai/evaluation-model")!
    static let modelID = "typesafe-ai/jev"
    static let gatewayProtocolVersion = "0.0.1"
    static let evaluationModelSpecificationVersion = "4"

    static let yesOptionKey = "yes"
    static let noOptionKey = "no"

    static func questionPayload(_ question: JevQuestion) -> [String: Any] {
        switch question {
        case let .noul(instructions, criteria):
            return [
                "type": "choice",
                "instructions": instructions,
                "criteria": [
                    yesOptionKey: criteria?["true"] ?? "Yes",
                    noOptionKey: criteria?["false"] ?? "No"
                ]
            ]
        case .choice:
            return question.payload
        }
    }

    /// IDs of the questions that were sent as yes/no choices, so their answers
    /// can be turned back into noul probabilities.
    static func noulQuestionIDs(in questions: [String: JevQuestion]) -> Set<String> {
        Set(questions.compactMap { questionID, question in
            if case .noul = question { return questionID }
            return nil
        })
    }

    static func requestBody(state: [String: Any], questions: [String: JevQuestion]) -> [String: Any] {
        [
            "state": state,
            "questions": questions.mapValues(questionPayload),
            // Only route to providers with zero data retention, and opt this
            // screen text out of prompt training.
            "providerOptions": [
                "gateway": ["zeroDataRetention": true, "disallowPromptTraining": true]
            ]
        ]
    }

    static func urlRequest(
        apiKey: String,
        state: [String: Any],
        questions: [String: JevQuestion]
    ) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(gatewayProtocolVersion, forHTTPHeaderField: "ai-gateway-protocol-version")
        request.setValue("api-key", forHTTPHeaderField: "ai-gateway-auth-method")
        request.setValue(evaluationModelSpecificationVersion, forHTTPHeaderField: "ai-evaluation-model-specification-version")
        request.setValue(modelID, forHTTPHeaderField: "ai-model-id")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(state: state, questions: questions))
        return request
    }

    static func decodeResponse(_ data: Data, noulQuestionIDs: Set<String>, modelID: String = modelID) throws -> JevResponse {
        let gatewayResponse = try JSONDecoder().decode(GatewayEvaluationResponse.self, from: data)
        var answers: [String: JevAnswer] = [:]
        for (questionID, gatewayAnswer) in gatewayResponse.answers {
            if noulQuestionIDs.contains(questionID) {
                answers[questionID] = JevAnswer(
                    type: "noul",
                    noul: yesProbability(from: gatewayAnswer),
                    choice: nil, score: nil, confidence: nil, probabilities: nil
                )
                continue
            }
            answers[questionID] = JevAnswer(
                type: gatewayAnswer.type == "boolean" ? "noul" : gatewayAnswer.type,
                noul: gatewayAnswer.probability,
                choice: gatewayAnswer.choice,
                score: gatewayAnswer.score,
                confidence: nil,
                probabilities: gatewayAnswer.probabilities
            )
        }
        return JevResponse(
            answers: answers,
            model: modelID,
            usage: JevResponse.Usage(
                input_tokens: gatewayResponse.usage?.inputTokens.map { Int($0) },
                output_tokens: gatewayResponse.usage?.outputTokens.map { Int($0) }
            )
        )
    }

    private static func yesProbability(from gatewayAnswer: GatewayEvaluationAnswer) -> Double? {
        if let probability = gatewayAnswer.probability { return probability }
        if let yesProbability = gatewayAnswer.probabilities?[yesOptionKey] { return yesProbability }
        guard let choice = gatewayAnswer.choice else { return nil }
        return choice == yesOptionKey ? 1 : 0
    }

    private struct GatewayEvaluationResponse: Decodable {
        let answers: [String: GatewayEvaluationAnswer]
        let usage: GatewayEvaluationUsage?
    }

    private struct GatewayEvaluationAnswer: Decodable {
        let type: String?
        let choice: String?
        let score: Double?
        /// Only on "boolean" answers: the model's P(true).
        let probability: Double?
        let probabilities: [String: Double]?
    }

    /// Decoded as Double because the spec only promises JSON numbers.
    /// Vercel sends camelCase, OpenRouter snake_case.
    private struct GatewayEvaluationUsage: Decodable {
        let inputTokens: Double?
        let outputTokens: Double?

        enum CodingKeys: String, CodingKey {
            case inputTokens, outputTokens
            case input_tokens, output_tokens
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            inputTokens = try container.decodeIfPresent(Double.self, forKey: .inputTokens)
                ?? container.decodeIfPresent(Double.self, forKey: .input_tokens)
            outputTokens = try container.decodeIfPresent(Double.self, forKey: .outputTokens)
                ?? container.decodeIfPresent(Double.self, forKey: .output_tokens)
        }
    }
}

// MARK: - OpenRouter transport

/// Sends Jev questions to OpenRouter's alpha Decisions endpoint (model
/// "~typesafe/jev-latest"). Note the endpoint sits at the origin, not under
/// /api/v1. Questions use the same choice-only encoding as the Vercel route,
/// and answers go through the same decoder.
nonisolated enum JevOpenRouter {
    static let endpoint = URL(string: "https://openrouter.ai/api/alpha/decisions")!
    static let modelID = "~typesafe/jev-latest"

    static func urlRequest(
        apiKey: String,
        state: [String: Any],
        questions: [String: JevQuestion]
    ) throws -> URLRequest {
        let body: [String: Any] = [
            "model": modelID,
            "state": state,
            "questions": questions.mapValues(JevVercelGateway.questionPayload),
            // Keep screen text out of provider logs and training, and never
            // silently fall back to a different provider.
            "provider": ["data_collection": "deny", "zdr": true, "allow_fallbacks": false]
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func decodeResponse(_ data: Data, noulQuestionIDs: Set<String>) throws -> JevResponse {
        try JevVercelGateway.decodeResponse(data, noulQuestionIDs: noulQuestionIDs, modelID: modelID)
    }
}
