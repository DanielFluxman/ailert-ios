// LLMService.swift
// Modular LLM API client - currently configured for OpenAI GPT-4
// Easy to swap providers by conforming to LLMProvider protocol

import Foundation
import Combine

// MARK: - LLM Provider Protocol

/// Protocol for LLM providers - implement this to add new providers
protocol LLMProvider {
    var name: String { get }
    func complete(messages: [LLMMessage], temperature: Double) async throws -> LLMResponse
}

// MARK: - LLM Messages

struct LLMMessage: Codable {
    let role: LLMRole
    let content: String
}

enum LLMRole: String, Codable {
    case system
    case user
    case assistant
}

struct LLMResponse {
    let content: String
    let tokensUsed: Int?
    let finishReason: String?
}

// MARK: - LLM Errors

enum LLMError: LocalizedError {
    case missingAPIKey
    case networkError(Error)
    case invalidResponse
    case rateLimited
    case serverError(String)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "API key not configured"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .invalidResponse: return "Invalid response from LLM"
        case .rateLimited: return "Rate limited - please wait"
        case .serverError(let msg): return "Server error: \(msg)"
        case .timeout: return "Request timed out"
        }
    }
}

// MARK: - LLM Service

@MainActor
class LLMService: ObservableObject {
    static let shared = LLMService()
    
    @Published var isLoading: Bool = false
    @Published var lastError: LLMError?
    
    private var provider: LLMProvider
    private let timeout: TimeInterval = 30
    
    private init() {
        // Default to OpenAI GPT-4
        self.provider = OpenAIProvider()
    }
    
    /// Switch to a different LLM provider
    func setProvider(_ provider: LLMProvider) {
        self.provider = provider
    }
    
    /// Send a completion request to the LLM
    func complete(
        systemPrompt: String,
        userPrompt: String,
        temperature: Double = 0.7
    ) async throws -> String {
        let messages = [
            LLMMessage(role: .system, content: systemPrompt),
            LLMMessage(role: .user, content: userPrompt)
        ]
        
        return try await complete(messages: messages, temperature: temperature)
    }
    
    /// Send a multi-turn conversation to the LLM
    func complete(
        messages: [LLMMessage],
        temperature: Double = 0.7
    ) async throws -> String {
        isLoading = true
        lastError = nil
        
        defer { isLoading = false }
        
        do {
            let response = try await provider.complete(
                messages: messages,
                temperature: temperature
            )
            return response.content
        } catch let error as LLMError {
            lastError = error
            throw error
        } catch {
            let llmError = LLMError.networkError(error)
            lastError = llmError
            throw llmError
        }
    }
}

// MARK: - OpenAI Provider

class OpenAIProvider: LLMProvider {
    let name = "OpenAI GPT-4"
    
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let model = "gpt-4-turbo-preview"
    
    /// Get API key from environment or settings
    /// IMPORTANT: Never commit API keys - use environment variables or secure storage
    private var apiKey: String? {
        // Check environment first
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            return envKey
        }
        // Fall back to UserDefaults (set by user in settings)
        return UserDefaults.standard.string(forKey: "openai_api_key")
    }
    
    func complete(messages: [LLMMessage], temperature: Double) async throws -> LLMResponse {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw LLMError.missingAPIKey
        }
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "temperature": temperature,
            "max_tokens": 500
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw LLMError.rateLimited
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.serverError(errorMessage)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse
        }
        
        let usage = json["usage"] as? [String: Any]
        let totalTokens = usage?["total_tokens"] as? Int
        let finishReason = firstChoice["finish_reason"] as? String
        
        return LLMResponse(
            content: content,
            tokensUsed: totalTokens,
            finishReason: finishReason
        )
    }
}

// MARK: - Additional Providers (Easy to add)

/*
 To add a new provider (e.g., Anthropic Claude, Google Gemini):
 
 1. Create a new class conforming to LLMProvider
 2. Implement the complete(messages:temperature:) method
 3. Switch providers using: LLMService.shared.setProvider(YourProvider())
 
 Example:
 
 class AnthropicProvider: LLMProvider {
     let name = "Anthropic Claude"
     
     func complete(messages: [LLMMessage], temperature: Double) async throws -> LLMResponse {
         // Implement Anthropic API call
     }
 }
 */
