import Foundation
import Combine

@MainActor
class MessageManager: ObservableObject {
    @Published var messages: [any Message] = []
    @Published var isLoading = false
    @Published var error: OpenCodeError?
    @Published var contentUpdateId: UUID = UUID() // Triggers scroll updates during streaming

    private let apiClient = OpenCodeAPIClient.shared
    private let eventClient = EventClient.shared
    private var cancellables = Set<AnyCancellable>()
    private var eventListenerTask: Task<Void, Never>?

    func fetchMessages(sessionID: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await apiClient.getMessages(sessionID: sessionID)
            messages = response
            error = nil
        } catch {
            if let openCodeError = error as? OpenCodeError {
                self.error = openCodeError
            } else {
                self.error = .networkError(error)
            }
            throw error
        }
    }

    func sendMessage(sessionID: String, prompt: String, agent: String? = nil) async throws -> Bool {
        isLoading = true
        defer { isLoading = false }

        do {
            return try await apiClient.sendMessage(sessionID: sessionID, prompt: prompt, agent: agent)
        } catch {
            if let openCodeError = error as? OpenCodeError {
                self.error = openCodeError
            } else {
                self.error = .networkError(error)
            }
            throw error
        }
    }

    // Track streaming state
    private var streamingMessageId: String?
    private var streamingPartsJson: [String: [String: Any]] = [:] // partID -> raw JSON dict
    private var userMessageIds: Set<String> = [] // Track user message IDs to avoid duplicates
    
    /// Sends a message and streams incremental updates via SSE
    /// Uses prompt_async + event stream for real-time token streaming
    func sendMessageWithStream(sessionID: String, prompt: String, agent: String? = nil) -> AsyncStream<Void> {
        return AsyncStream { continuation in
            Task { @MainActor in
                isLoading = true
                streamingMessageId = nil
                streamingPartsJson = [:]
                
                // Track existing user message IDs so we don't duplicate them
                userMessageIds = Set(messages.filter { $0.role == .user }.map { $0.id })
                
                print("MessageManager: Starting incremental stream for session \(sessionID)")
                print("MessageManager: Agent: \(agent ?? "default")")
                print("MessageManager: Tracking \(userMessageIds.count) existing user messages")
                
                do {
                    // Start SSE listener first
                    let eventStream = eventClient.eventStream()
                    
                    // Send the prompt async (fire and forget)
                    print("MessageManager: Sending prompt_async")
                    _ = try await apiClient.sendMessage(sessionID: sessionID, prompt: prompt, agent: agent)
                    print("MessageManager: prompt_async sent, listening for events...")
                    
                    // Listen for events
                    for try await event in eventStream {
                        switch event.type {
                        case "message.updated":
                            // Track user messages from server so we don't create duplicates
                            if let info = event.properties["info"] as? [String: Any],
                               let role = info["role"] as? String,
                               role == "user",
                               let messageID = info["id"] as? String {
                                print("MessageManager: Server user message detected: \(messageID)")
                                userMessageIds.insert(messageID)
                            }
                            
                        case "message.part.updated":
                            if let partData = event.properties["part"] as? [String: Any],
                               let partSessionID = partData["sessionID"] as? String,
                               partSessionID == sessionID,
                               let messageID = partData["messageID"] as? String,
                               let partID = partData["id"] as? String,
                               let partTypeStr = partData["type"] as? String {
                                
                                // Skip if this is a user message (already displayed locally or from server)
                                if userMessageIds.contains(messageID) {
                                    continue
                                }
                                
                                // Also skip if message already exists and is a user message
                                if let existingMsg = messages.first(where: { $0.id == messageID }), existingMsg.role == .user {
                                    userMessageIds.insert(messageID)
                                    continue
                                }
                                
                                // Get the full text and delta
                                let fullText = partData["text"] as? String ?? ""
                                let delta = event.properties["delta"] as? String
                                
                                if let delta = delta, !delta.isEmpty {
                                    print("MessageManager: Text delta (\(delta.count) chars)")
                                }
                                
                                // Update streaming state and UI - pass full part data
                                updateStreamingMessage(
                                    messageID: messageID,
                                    sessionID: sessionID,
                                    partData: partData
                                )
                                
                                contentUpdateId = UUID() // Trigger UI update
                                continuation.yield(())
                            }
                            
                        case "session.idle":
                            print("MessageManager: Session idle - generation complete")
                            // Fetch final state to get complete message with all metadata
                            await refreshMessages(sessionID: sessionID)
                            streamingMessageId = nil
                            streamingPartsJson = [:]
                            userMessageIds = []
                            contentUpdateId = UUID()
                            continuation.finish()
                            isLoading = false
                            return
                            
                        case "session.error":
                            print("MessageManager: Session error event")
                            if let errorInfo = event.properties["error"] as? [String: Any],
                               let errorMessage = errorInfo["message"] as? String {
                                print("MessageManager: Error: \(errorMessage)")
                            }
                            
                        default:
                            break // Silently ignore other events
                        }
                    }
                    
                    error = nil
                } catch {
                    print("MessageManager: Stream error: \(error)")
                    if let openCodeError = error as? OpenCodeError {
                        self.error = openCodeError
                    } else {
                        self.error = .networkError(error)
                    }
                }

                isLoading = false
                streamingMessageId = nil
                streamingPartsJson = [:]
                userMessageIds = []
                continuation.finish()
                print("MessageManager: Stream finished, final message count: \(messages.count)")
            }
        }
    }
    
    /// Refreshes messages by merging with existing ones to avoid UI flicker
    private func refreshMessages(sessionID: String) async {
        do {
            let freshMessages = try await apiClient.getMessages(sessionID: sessionID)
            
            // Merge: update existing messages in place, add new ones
            for freshMsg in freshMessages {
                if let index = messages.firstIndex(where: { $0.id == freshMsg.id }) {
                    messages[index] = freshMsg
                } else {
                    // Find correct insertion point to maintain order
                    let insertIndex = messages.firstIndex(where: { $0.timeCreated > freshMsg.timeCreated }) ?? messages.endIndex
                    messages.insert(freshMsg, at: insertIndex)
                }
            }
            
            // Remove any messages not in fresh list (e.g., our temp user message if server assigned different ID)
            let freshIds = Set(freshMessages.map { $0.id })
            messages.removeAll { !freshIds.contains($0.id) }
            
            print("MessageManager: Refreshed messages, count: \(messages.count)")
        } catch {
            print("MessageManager: Failed to refresh messages: \(error)")
        }
    }
    
    /// Updates the streaming message in the messages array
    private func updateStreamingMessage(messageID: String, sessionID: String, partData: [String: Any]) {
        guard let partID = partData["id"] as? String else { return }
        
        // Store the full part data
        streamingPartsJson[partID] = partData
        
        // Check if this is a new message
        if streamingMessageId != messageID {
            streamingMessageId = messageID
            print("MessageManager: New streaming message: \(messageID)")
        }
        
        // Build the message from streaming parts
        let partsForMessage = streamingPartsJson.values.filter { ($0["messageID"] as? String) == messageID }
        
        // Convert parts to JSON
        guard let partsData = try? JSONSerialization.data(withJSONObject: Array(partsForMessage)),
              let partsJsonString = String(data: partsData, encoding: .utf8) else {
            print("MessageManager: Failed to serialize parts")
            return
        }
        
        let messageJSON = """
        {
            "info": {
                "id": "\(messageID)",
                "sessionID": "\(sessionID)",
                "role": "assistant",
                "time": { "created": \(Int(Date().timeIntervalSince1970 * 1000)) },
                "modelID": "streaming",
                "providerID": "streaming",
                "agent": "assistant",
                "tokens": { "input": 0, "output": 0, "reasoning": 0, "cache": { "read": 0, "write": 0 } },
                "cost": 0
            },
            "parts": \(partsJsonString)
        }
        """
        
        guard let data = messageJSON.data(using: .utf8),
              let newMessage = try? JSONDecoder().decode(APIResponseMessage.self, from: data) else {
            print("MessageManager: Failed to decode streaming message")
            return
        }
        
        // Update or add the message
        if let index = messages.firstIndex(where: { $0.id == messageID }) {
            messages[index] = newMessage
        } else {
            messages.append(newMessage)
            print("MessageManager: Added new streaming message, count: \(messages.count)")
        }
    }

    func startEventListener(sessionID: String) {
        // Only start if not already listening to this session
        if eventListenerTask != nil {
            print("MessageManager: Event listener already running, stopping first")
            stopEventListener()
        }

        eventListenerTask = Task { @MainActor in
            print("MessageManager: Starting event listener for session \(sessionID)")

            let eventStream = eventClient.eventStream()

            do {
                for try await event in eventStream {
                    print("MessageManager: Processing event type: \(event.type)")

                    switch event.type {
                    case "message.updated":
                        if let info = event.properties["info"] as? [String: Any],
                           let eventSessionID = info["sessionID"] as? String,
                           eventSessionID == sessionID {
                            print("MessageManager: Message updated for our session")

                            if let jsonData = try? JSONSerialization.data(withJSONObject: info),
                               let message = try? JSONDecoder().decode(APIResponseMessage.self, from: jsonData) {
                                await self.handleMessageUpdate(message)
                            }
                        }

                    case "message.part.updated":
                        if let part = event.properties["part"] as? [String: Any],
                           let eventSessionID = part["sessionID"] as? String,
                           eventSessionID == sessionID,
                           let messageID = part["messageID"] as? String,
                           let partID = part["id"] as? String {
                            print("MessageManager: Part updated: \(partID) for message \(messageID)")

                            // Handle streaming for existing messages that might be in progress
                            await self.handleStreamingPartUpdate(part: part, messageID: messageID, sessionID: sessionID)
                        }

                    case "session.status":
                        if let statusProps = event.properties["status"] as? [String: Any],
                           let statusType = statusProps["type"] as? String {
                            print("MessageManager: Session status: \(statusType)")
                        }

                    case "session.idle":
                        print("MessageManager: Session is now idle")
                        // Refresh messages when session becomes idle to get final state
                        try? await fetchMessages(sessionID: sessionID)

                    case "session.updated":
                        print("MessageManager: Session updated")

                    default:
                        print("MessageManager: Ignoring event: \(event.type)")
                    }
                }
            } catch {
                print("MessageManager: Event stream error: \(error)")
            }

            print("MessageManager: Event listener finished")
        }
    }

    private func handlePartUpdate(part: [String: Any], messageID: String, sessionID: String) async {
        print("MessageManager: Handling part update for message \(messageID)")

        if let text = part["text"] as? String,
           let delta = part["delta"] as? String {
            print("MessageManager: Incremental update - current: \(text.count) chars, delta: \(delta.count) chars")
        }

        if let partID = part["id"] as? String,
           let typeString = part["type"] as? String,
           let partType = MessagePartType(rawValue: typeString) {
            print("MessageManager: Part \(partID) is type \(partType)")
        }

        if let state = part["state"] as? [String: Any],
           let status = state["status"] as? String {
            print("MessageManager: Tool status: \(status)")
        }

        print("MessageManager: Refreshing messages for session \(sessionID)")
        try? await fetchMessages(sessionID: sessionID)
    }

    /// Handle streaming part updates for existing sessions (not initiated by this client)
    private func handleStreamingPartUpdate(part: [String: Any], messageID: String, sessionID: String) async {
        print("MessageManager: Handling streaming part update for existing message \(messageID)")
        
        // Skip user messages (should already be loaded)
        if let existingMessage = messages.first(where: { $0.id == messageID }), existingMessage.role == .user {
            print("MessageManager: Skipping user message update")
            return
        }
        
        // Use the same logic as sendMessageWithStream for streaming updates
        if let text = part["text"] as? String {
            print("MessageManager: Streaming text update: \(text.count) characters")
        }
        
        if let delta = part["delta"] as? String {
            print("MessageManager: Streaming delta: \(delta.count) characters")
        }
        
        // For existing sessions, refresh messages to get latest state rather than building streaming temp message
        // This ensures we get complete message data including metadata
        print("MessageManager: Refreshing messages due to streaming update")
        try? await fetchMessages(sessionID: sessionID)
        contentUpdateId = UUID() // Trigger UI update
    }

    func stopEventListener() {
        eventListenerTask?.cancel()
        eventListenerTask = nil
        eventClient.stop()
        print("MessageManager: Event listener stopped")
    }

    private func handleMessageUpdate(_ message: APIResponseMessage) async {
        print("MessageManager: Handling message update: \(message.id)")

        if message.role == .user {
            if !messages.contains(where: { $0.id == message.id }) {
                messages.append(message)
                contentUpdateId = UUID() // Trigger scroll
                print("MessageManager: Added user message from event, new count: \(messages.count)")
            }
        } else if message.role == .assistant {
            if let index = messages.firstIndex(where: { $0.role == .assistant && $0.id == message.id }) {
                messages[index] = message
                contentUpdateId = UUID() // Trigger scroll on update
                print("MessageManager: Updated assistant message from event at index \(index)")
            } else {
                messages.append(message)
                contentUpdateId = UUID() // Trigger scroll
                print("MessageManager: Added new assistant message from event, new count: \(messages.count)")
            }
        }
    }

    func clearMessages() {
        messages.removeAll()
        stopEventListener()
    }
}
