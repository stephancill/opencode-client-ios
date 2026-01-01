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

### 3.3 Prompt Input ✅
- Multi-line text input
- File attachment picker (photo picker, document picker)
- Send button with loading state
- **Cancel/Stop button** - Cancel in-progress message requests with red X icon
- Uses `/session/:id/abort` API endpoint
- Task cancellation with `Task.cancel()`
- Proper loading state management

## Phase 4: Permissions UI ✅

### 4.1 Permission Alerts ✅
- Modal alerts for pending permissions
- Display: title, type, metadata (command/file paths)
- Three buttons: **Deny**, **Allow Once**, **Always Allow**
- Clear warning for risky operations

### 4.2 Permission Manager ✅
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
 │  ├─ MessageManager.swift
 │  └─ PermissionManager.swift
 ├─ Views/ ✅
 │  ├─ Chat/
 │  │  └─ ChatView.swift
 │  ├─ Permissions/
 │  │  └─ PermissionViews.swift
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

**Current Build Status**: ✅ Building successfully for iOS Simulator (no errors or warnings)

**Build Command**:
```bash
xcodebuild -scheme RemoteAgent -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

**Clean Build (if needed)**:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/RemoteAgent-*
xcodebuild -scheme RemoteAgent -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

**Deployment Target**: iOS 18.0

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
- [x] Managers: SessionManager (session lifecycle), MessageManager (message fetching), PermissionManager (polling)
- [x] Views: SessionListView (with create/delete), ChatView (message display + permissions), SettingsView (VPS URL)
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
- [x] Permission Alerts: Added permission alert UI in ChatView with polling every 5 seconds
- [x] Permission Response: Deny/Allow Once/Always Allow buttons with API integration
- [x] Permission Icons: Color-coded icons by permission type (file, command, network, external_directory)
- [x] Cancel Request: Red X button appears when loading, calls `/session/:id/abort` endpoint

### ⚠️ Known Issues
- **Print console logging needs cleanup** - Debug print statements throughout codebase
- **Build warnings**: Timer fires on background thread, causing "Publishing changes from background threads" warning (non-blocking)

### ✅ Completed
- [x] Testing streaming with various message types (text, tools, files, reasoning)
- [x] **Tool Call Display: Enhanced to show full command, tool input/output, status indicators**
- [x] **Permission alerts UI** - Created PermissionManager with polling, PermissionViews with alert/detail/list views
- [x] **Permission Manager** - Singleton with automatic polling every 5 seconds
- [x] **Permission Alert Card** - Shows title, type, metadata with Deny/Allow Once/Always Allow buttons
- [x] **Permission List View** - Displays all pending permissions with tap for details
- [x] **Permission Detail View** - Full permission details with action buttons
- [x] **Permission Integration in ChatView** - Alerts appear at top of chat for current session only

### 📋 Pending
- [ ] Workspace/project selector
- [ ] Token/cost display per session
- [ ] Offline support
- [ ] Session actions (fork, share, revert)

### ⏳ In Progress
- [ ] **TESTING: Permission alerts** (verify alerts appear and work correctly)
- [ ] **TESTING: Cancel request** (verify cancel button works with local server)

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
 │  ├─ MessageManager.swift ✅ (Added sendMessageWithStream for streaming, proper message handling)
 │  └─ PermissionManager.swift ✅ (Polling permissions every 5 seconds, responding to permissions)
 ├─ Views/
 │  ├─ Chat/
 │  │  └─ ChatView.swift ✅ (Streaming, cancel, permission alerts, auto-scroll)
 │  ├─ Permissions/
 │  │  └─ PermissionViews.swift ✅ (PermissionListView, PermissionDetailView, PermissionAlertView, PermissionAlertCard)
 │  ├─ Sessions/ (empty)
 │  ├─ Shared/ (empty)
 │  ├─ ContentView.swift ✅ (TabView navigation)
 │  └─ SettingsView.swift ✅
├─ SessionListView.swift ✅
└─ RemoteAgentApp.swift ✅
```

### 🎯 Next Steps for Developer

1. **Test Permission Alerts**:
       - Verify permission alerts appear when pending permissions exist
       - Test Deny/Allow Once/Always Allow buttons with local server
       - Confirm polling works (every 5 seconds)
       - Verify alerts filter correctly by session ID
       - Test with different permission types (file, command, external_directory)

2. **Test Cancel Functionality**:
       - Send a message and tap cancel button while loading
       - Verify session aborts on server
       - Confirm UI returns to normal state
       - Test cancel during various states (tool running, streaming text)

3. **Improve Chat Experience**:
       - Add pull-to-refresh to reload messages (currently has refreshable modifier but needs testing)
       - Add error display for failed messages
       - Improve auto-scroll behavior

4. **Add Token/Cost Display**:
       - Show token usage per session in session list
       - Display cost in session detail view
       - Add cost aggregation for all sessions

5. **Workspace/Project Selector**:
       - Create project list view with `/home/opencode/projects/*` directories
       - Add workspace selection toggle (Project vs Control mode)
       - Implement add/edit/delete project functionality

6. **Add Permissions Tab to Navigation** (Optional):
       - Add Permissions tab to ContentView TabView
       - Show badge when pending permissions exist
       - Allow quick access to approve/deny permissions
       - Note: Currently permission alerts appear directly in ChatView for active session

### ✅ Recently Completed
- **Cancel Request Functionality**: Added ability to cancel in-progress message requests
   - Red X icon (`xmark.circle.fill`) appears when loading
   - Button action toggles between send and cancel
   - Calls `/session/:id/abort` endpoint to stop session
   - Task cancellation with Swift `Task.cancel()`
   - Proper loading state management

- **Permission Alerts in ChatView**: Added permission alert UI directly in chat interface
   - PermissionManager polls `/permission` endpoint every 5 seconds
   - Pending permissions filtered by current session ID
   - Alert card shows at top of chat when permission is pending
   - Displays permission title, type, and metadata (file paths, commands, etc.)
   - Three action buttons: Deny, Allow Once, Always Allow
   - Color-coded icons by permission type (file, command, network, external_directory, etc.)
   - Uses `.regularMaterial` background for glassmorphism effect
   - Shadows and rounded corners for modern iOS design
   - API response calls use correct session directory parameter
       - Add workspace selection toggle (Project vs Control mode)
       - Implement add/edit/delete project functionality

### 🔧 Technical Notes
- SwiftUI Navigation APIs changed in iOS 18 - using simpler patterns
- Complex view hierarchies previously caused build issues - kept minimal
- All model types compile cleanly
- Project uses Xcode file system synchronization (auto-adds new files)
- SessionManager is a singleton: `SessionManager.shared`
- MessageManager handles message fetching and sending (with streaming support)
- PermissionManager is a singleton: `PermissionManager.shared` with automatic polling
- Permission alerts use `@StateObject` to observe `PermissionManager.shared` published properties
- Permission alerts filter by `sessionID` to show only relevant permissions in current chat
- Permission endpoint returns array of `[Permission]` objects with metadata
- Permission types: external_directory, command, file, network, system, shell
- Permission responses: once, always, reject (enum with rawValue for API)
- PermissionManager polls `/permission` endpoint every 5 seconds using Timer
- PermissionManager updates `@Published` properties from background thread (causes warning but non-blocking)
- Markdown Support: Added MarkdownView component using native iOS Text(LocalizedStringKey) for rendering markdown content in text messages and generic parts
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

**Permission System Flow:**
1. `PermissionManager` starts singleton on app launch
2. Timer fires every 5 seconds to call `fetchPermissions()`
3. `fetchPermissions()` calls `GET /permission` API endpoint
4. Permissions array decoded and stored in `@Published var pendingPermissions`
5. `ChatView` observes `PermissionManager.shared.pendingPermissions`
6. Alert shows when permission with matching `sessionID` is found
7. User taps Deny/Allow Once/Always Allow button
8. `respondToPermission()` calls `POST /session/:id/permissions/:permId` with response type
9. Permissions refreshed after response
10. Alert disappears when permission is approved/denied

**Cancel Request Flow:**
1. User sends message, loading state set to true
2. Red X icon appears in place of send button
3. User taps cancel button
4. `sendTask.cancel()` called to stop streaming task
5. `abortSession()` API call sends `POST /session/:id/abort`
6. Loading state set to false, send button returns
7. UI returns to normal state

## User Added Todos

### High Priority
- ~~new session shouldn't prompt for title and should just go directly to chat with default name (server has automatic naming logic)~~ ✅
- ~~markdown support~~ ✅
- fix streaming for when clicking into existing sessions that are busy
- skeleton loading states for session list and chat view
- improve handling of existing sessions with many messages
- @ mentions for projects and files
- show code edits
