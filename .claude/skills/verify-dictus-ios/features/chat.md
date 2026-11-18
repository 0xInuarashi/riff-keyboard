# On-device chat

## Sub-features

| ID | Behavior |
| --- | --- |
| `chat.model` | Choose the available Apple system model or download and select a local model. |
| `chat.conversation` | Send messages, stop generation, retry an unanswered message, or start a new chat. |

## How to get to it

Open **Chat**, tap the model name at the top, and select a model. Type a message and tap Send. Chat and Smart Modes remember separate selections and share their downloaded model files.

## Driving it with axe + Argent

1. Open the Chat tab, tap `chat.model`, and select a downloaded model by `rewriteModel.<id>`. Tap Done.
2. Focus `chat.compose`, type “My favorite fruit is a pear.” and tap `chat.send`.
3. Wait for `chat.message.assistant`. Send “What is my favorite fruit? Reply in one word.” and check the latest reply.
4. Tap `chat.new`, confirm New chat, and check that the composer is ready for a fresh conversation.

## Gotchas

- The simulator can exercise downloadable models. Use a compatible physical iPhone to check the Apple Intelligence picker, on-device performance, and memory use.
- On iOS 27, the picker displays the variant returned by Apple's system model API. Each device provides a single on-device Apple model.
- Chat stays in memory while the app is running. The model's context keeps the latest message and as many of the recent six exchanges as fit.
