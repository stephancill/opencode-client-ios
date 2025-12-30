# iOS Client Implementation Plan

## 🚨 IMPORTANT: Development Protocol
**NEVER install or run the app yourself - ALWAYS ask user to run it in Xcode**
- Do not use `xcrun simctl install` or `xcrun simctl launch`
- Do not run `xcodebuild` with install/launch commands
- After making changes, simply build and ask user to test in Xcode
- This ensures user maintains control and avoids simulator conflicts

## Architecture Overview
**MVVM + SwiftUI** with modular components:
- **Network Layer**: API client with SSE support
- **State Management**: Combine publishers + ObservableObjects  
- **UI Components**: SwiftUI views for chat, sessions, permissions

## Phase 1: Core Network Layer ✅

### 1.1 API Client Foundation ✅
- `OpenCodeAPIClient`: Singleton for HTTP requests
- Configure base URL from Tailscale endpoint (`https://<vps>.<tailnet>.ts.net/`)
- Implement directory header middleware (`x-opencode-directory`)
- Error handling with typed `OpenCodeError`

### 1.2 API Models (Codable structs) ✅
- `Session`: id, title, directory, time, summary
- `Message`: id, role, time, agent, model, tokens, cost
- `MessagePart`: text, tool, reasoning, step-start/finish, file
- `Permission`: id, type, title, metadata, time
- `SessionStatus`: active/idle/completed states

### 1.3 API Endpoints ✅
```
GET  /session                           → List sessions
POST /session                           → Create session  
GET  /session/:id                       → Get session
GET  /session/:id/message               → Get messages
POST /session/:id/message               → Send message (stream)
POST /session/:id/prompt_async          → Send async
POST /session/:id/abort                 → Abort
GET  /permission                        → List pending
POST /session/:id/permissions/:permId    → Respond to permission
GET  /global/event                      → Global SSE
GET  /event?directory=...               → Directory SSE
```

### 1.4 SSE Implementation ✅
- `EventStream`: AsyncStream for SSE parsing
- `GlobalEventStream`: Monitor all sessions
- `DirectoryEventStream`: Per-project events (recommended)
- 30s heartbeat handling (WKWebView 60s timeout)
- Auto-reconnection with exponential backoff

## Phase 2: Session Management ✅

### 2.1 Session Store ✅
- `SessionManager`: ObservableObject managing sessions
- Store `(sessionID, directory)` tuples for directory-scoping
- Cache sessions locally with last sync timestamp
- List/create/delete operations

### 2.2 Workspace Selection ✅
- Mode toggle: **Project** vs **Control**
- Project mode: `/home/opencode/projects/<repo>`
- Control mode: `/home/opencode/control`
- Persistent workspace preference

### 2.3 Message Store ⏳
- `MessageManager`: Fetch and cache messages
- Incremental updates via SSE `message.updated` events
- Pagination support

## Phase 3: Chat Interface ⏳

### 3.1 Message List View
- `ChatView`: ScrollView with lazy loading
- Render user/assistant messages with timestamps
- Expand/collapse tool outputs
- Syntax highlight code blocks
- File attachments preview

### 3.2 Streaming UI
- Real-time text streaming for assistant responses
- Part-by-part updates (text, reasoning, tool states)
- `MessagePart` renderers:
  - TextPart: Markdown rendering
  - ToolPart: Pending → Running → Completed/Error states
  - StepStart/Finish: Step boundaries with cost/tokens
  - ReasoningPart: Collapsible reasoning view

### 3.3 Prompt Input
- Multi-line text input
- File attachment picker (photo picker, document picker)
- Send button with loading state

## Phase 4: Permissions UI ⏳

### 4.1 Permission Alerts
- Modal alerts for pending permissions
- Display: title, type, metadata (command/file paths)
- Three buttons: **Deny**, **Allow Once**, **Always Allow**
- Clear warning for risky operations

### 4.2 Permission Manager
- Poll `GET /permission` or watch `permission.updated` events
- Batch permission approval for same pattern
- Show permission history per session

## Phase 5: Navigation & UX ⏳

### 5.1 App Structure
```
TabView:
├─ Sessions (list of all sessions)
├─ Chat (current session view)
├─ Projects (workspace selector)
└─ Settings (VPS URL, debug logs)
```

### 5.2 Session List
- Group by workspace (control vs projects)
- Sort by `time.updated`
- Show status indicators (active/idle/error)
- Swipe actions: delete, archive

### 5.3 Project Selector
- List `/home/opencode/projects/*` directories
- Add new project (clone repo URL)
- Edit/delete projects

## Phase 6: Additional Features ⏳

### 6.1 Offline Support
- Cache last N messages per session
- Queue outgoing prompts when offline
- Sync on reconnection

### 6.2 Session Actions
- Fork session at any point
- Revert changes
- Share session (generate shareable link)
- View diff summary

### 6.3 Status & Monitoring
- Connection status indicator
- Session status badge
- Token/cost display per session
- Error banner with retry

## File Structure
```
RemoteAgent/
├─ Models/ ✅
│  ├─ OpenCodeError.swift (merged into APIClient.swift)
│  ├─ Session.swift
│  ├─ Message.swift (Full API response support)
│  ├─ MessagePart.swift (merged into Message.swift)
│  ├─ Permission.swift
│  └─ Event.swift
├─ Networking/ ✅
│  ├─ APIClient.swift (Includes OpenCodeError enum)
│  ├─ SSEClient.swift
│  └─ APIEndpoints.swift
├─ Managers/ ✅
│  ├─ SessionManager.swift
│  └─ MessageManager.swift
├─ Views/ ✅
│  ├─ Chat/
│  │  └─ ChatView.swift
│  ├─ Permissions/ (empty)
│  ├─ Sessions/ (empty)
│  ├─ Shared/ (empty)
│  ├─ ContentView.swift (TabView navigation)
│  ├─ SettingsView.swift
│  └─ SessionListView.swift
└─ RemoteAgentApp.swift
```

## Key Technical Decisions

### Tailscale Integration
- Assume iOS device has Tailscale installed
- VPS hostname resolved via mDNS (`vps.ts.net` or custom)
- No additional auth layer (trust via tailnet ACLs)

### SSE Handling
- Use `URLSession` with `EventSource` pattern
- Parse SSE lines: `data: {json}`
- Handle heartbeats to keep connection alive

### Error Handling
- Network errors: Show retry banner
- API errors: Display specific error messages
- Session aborted: Show abort notice

### State Management
- Combine publishers for reactive UI
- `@Published` properties for session/message lists
- Single source of truth per manager
- SessionManager is a singleton: `SessionManager.shared`
- MessageManager handles message fetching and sending
- APIClient base URL stored in UserDefaults: "baseURL" key
- Default VPS URL: "http://127.0.0.1:4096" (for local testing)

### API Response Structure
- Messages have `info` object containing message metadata
- Messages have `parts` array containing message components
- MessagePart types: text, file, tool, reasoning, step-start, step-finish
- Timestamps from API are in milliseconds, converted to Date objects
- Error handling includes detailed logging for debugging

### SwiftUI Navigation
- TabView for main navigation (Sessions, Chat, Projects, Settings)
- NavigationView wrapper provides toolbar support for each tab
- iOS 18 deployment target

## Build Commands

**Current Build Status**: ✅ Building successfully for iOS Simulator

**Build Command**:
```bash
xcodebuild -scheme RemoteAgent -sdk iphonesimulator -destination 'id=E7110220-3CF1-4A97-BFCC-D371846B068E' build
```

**Clean Build (if needed)**:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/RemoteAgent-*
xcodebuild -scheme RemoteAgent -sdk iphonesimulator -destination 'id=E7110220-3CF1-4A97-BFCC-D371846B068E' build
```

**Deployment Target**: iOS 18.0
**Simulator Device**: iPhone 16 Pro

**Install xcpretty for readable output** (optional):
```bash
gem install xcpretty
xcodebuild ... | xcpretty
```

## Testing Considerations
- Unit tests for API models (encoding/decoding)
- Mock API client for UI testing
- Integration tests with test VPS instance
- SSE reconnection simulation

## Implementation Progress

### ✅ Completed
- [x] Models: OpenCodeError, Session, Message, MessagePart, Permission, Event
- [x] Networking: APIClient (HTTP client), SSEClient (event streaming), APIEndpoints extension
- [x] Managers: SessionManager (session lifecycle), MessageManager (message fetching)
- [x] Views: SessionListView (with create/delete), ChatView (message display), SettingsView (VPS URL)
- [x] Navigation: TabView with NavigationView for proper toolbar support
- [x] Message Models: Fixed decoding to handle actual API response (info/parts structure)
- [x] MessagePart: Added proper decoding for all part types (text, tool, file, reasoning, steps)
- [x] API Client: Fixed sendMessage to use correct format (prompt + parts array)
- [x] Error Handling: Improved error logging and debugging
- [x] Build: Successfully building for iOS Simulator
- [x] Send Message: Fixed timeout issue by using async `/session/:id/prompt_async` endpoint
- [x] Message Polling: Added polling logic to wait for assistant response after sending
- [x] SSE Streaming: Rewrote SSEClient to use `URLSession.bytes` for true streaming
- [x] Streaming Endpoint: Added `sendMessageWithStream()` to API client using `POST /session/:id/message`
- [x] Message Manager: Added streaming support with `sendMessageWithStream()` method
- [x] ChatView: Updated to use streaming instead of polling
- [x] User Message Display: Fixed to show user message immediately when sent
- [x] UI Stability: Removed refreshID to prevent UI jumping during message updates
- [x] Message Decoding: Fixed "Unknown message type" error for user messages

### ⚠️ Known Issues
- **Current streaming shows entire message at once, not incrementally**
  - Server sends complete AI response as single JSON chunk
  - Messages appear instantly after stream completes (1-2 seconds of "loading")
  - Not true streaming where text appears character-by-character

### 📋 Pending

### 📋 Pending
- [ ] **TESTING: Streaming message display** (verify with various message types)
- [ ] Permission alerts UI
- [ ] Workspace/project selector
- [ ] Token/cost display per session
- [ ] Offline support
- [ ] Session actions (fork, share, revert)

### ⏳ In Progress
- [ ] **Implement proper incremental streaming** (server sends entire response, need to investigate for incremental)
- [ ] Testing streaming with various message types (text, tools, files, reasoning)

### 📋 Pending
- [ ] Permission alerts UI
- [ ] Workspace/project selector
- [ ] Token/cost display per session
- [ ] Offline support
- [ ] Session actions (fork, share, revert)

### 📁 Current Working Files
```
RemoteAgent/
├─ Models/
│  ├─ OpenCodeError.swift ✅
│  ├─ Session.swift ✅
│  ├─ Message.swift ✅ (Full API response structure support)
│  ├─ Permission.swift ✅
│  └─ Event.swift ✅
 ├─ Networking/
 │  ├─ APIClient.swift ✅ (Includes OpenCodeError enum)
 │  ├─ SSEClient.swift ✅ (Now uses URLSession.bytes for true streaming)
 │  └─ APIEndpoints.swift ✅ (Added sendMessageWithStream method)
 ├─ Managers/
 │  ├─ SessionManager.swift ✅
 │  └─ MessageManager.swift ✅ (Added sendMessageWithStream for streaming, proper message handling)
 ├─ Views/
 │  ├─ Chat/
 │  │  └─ ChatView.swift ✅ (Uses streaming, user message shows immediately, no UI jumping)
│  ├─ Permissions/ (empty)
│  ├─ Sessions/ (empty)
│  ├─ Shared/ (empty)
│  ├─ ContentView.swift ✅ (TabView navigation)
│  └─ SettingsView.swift ✅
├─ SessionListView.swift ✅
└─ RemoteAgentApp.swift ✅
```

### 🎯 Next Steps for Developer

1. **Investigate True Streaming Implementation**:
      - Examine OpenCode source code at `/Users/stephan/environments/external/opencode`
      - Look for incremental streaming endpoints or configuration options
      - Check if server supports SSE events during AI generation (not just at end)
      - Possible approaches:
        - Different endpoint for incremental streaming
        - Server configuration to send chunks as they arrive
        - WebSocket support for real-time updates
      - May need to modify server or use different API pattern

2. **Test Current Streaming**:
      - Verify messages appear without needing to navigate away
      - Test with different message types (text, tools, files, reasoning)
      - Confirm message parts display correctly

3. **Continue with Permissions**:
      - Create PermissionManager to fetch pending permissions
      - Build permission alert UI with Deny/Allow Once/Always Allow buttons
      - Integrate permission responses with API

4. **Improve Chat Experience**:
      - Add pull-to-refresh to reload messages
      - Add error display for failed messages
      - Implement auto-scroll to latest message

### 🔧 Technical Notes
- SwiftUI Navigation APIs changed in iOS 18 - using simpler patterns
- Complex view hierarchies previously caused build issues - kept minimal
- All model types compile cleanly
- Project uses Xcode file system synchronization (auto-adds new files)
- SessionManager is a singleton: `SessionManager.shared`
- MessageManager handles message fetching and sending (with streaming support)
- APIClient base URL stored in UserDefaults: "baseURL" key
- Default VPS URL: "https://vps.ts.net"
- API response structure: Messages have `info` object and `parts` array
- MessagePart types: text, file, tool, reasoning, step-start, step-finish, etc.
- Error handling includes detailed logging for debugging
- Timestamps from API are in milliseconds, converted to Date objects

### 📊 Streaming Implementation (CURRENT STATE)
**Previous Problem with Polling:**
- `POST /session/:id/prompt_async` returns immediately (204), but polling was unreliable
- Messages were incomplete when first returned by `GET /session/:id/message`
- Race conditions between message creation and part updates
- UI updates not triggered consistently despite `@Published` properties
- Required user to navigate away and back to see complete messages

**Current Solution: Endpoint Streaming**
- Endpoint: `POST /session/:sessionID/message` (streaming)
- Returns: SSE stream with complete message object when response completes
- Flow: Send prompt → Stream response → Update UI

**Implementation Details:**
1. ✅ Updated `SSEClient` to use `URLSession.bytes(for: request)` for true streaming
2. ✅ Parse SSE data incrementally as it arrives (not at end of response)
3. ✅ Use `AsyncThrowingStream` to yield decoded messages
4. ✅ Added `sendMessageWithStream()` method to API client
5. ✅ Updated `MessageManager` to add messages as they arrive
6. ✅ Updated `ChatView` to consume streaming messages
7. ✅ Fixed user message display (shows immediately when sent)
8. ✅ Removed `refreshID` to prevent UI jumping

**Current Behavior:**
- User message appears immediately in UI when sent
- Server waits for complete AI response before sending
- Entire response arrives as single JSON chunk (not incremental)
- UI shows "loading" for 1-2 seconds (AI generation time)
- Complete assistant message appears all at once

**Not Yet Implemented: True Incremental Streaming**
- Server sends complete message object, not character-by-character chunks
- Would require examining OpenCode source to find incremental streaming endpoint
- Or server modification to send SSE events as text generates

**SSE Format (from server):**
```
{"info": {...}, "parts": [...]}
```
Note: Server sends raw JSON, not in standard SSE `data:` format

**Message Flow:**
1. User sends prompt via `ChatView.sendMessage()`
2. User message created and added to `@Published` array immediately
3. `MessageManager.sendMessageWithStream()` creates streaming connection
4. API client sends POST request to `/session/:id/message`
5. Server waits for AI response completion
6. Server streams SSE response with complete message object
7. Assistant message is added to `@Published` array
8. UI updates automatically via SwiftUI's reactive system
