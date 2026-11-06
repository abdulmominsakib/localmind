# Use LocalMind from another app

LocalMind for Android can serve a model already loaded on your phone. The
server exposes the OpenAI Chat Completions API, and prompts are processed by
the loaded model on your phone.

1. In **Settings → On-Device Inference → Manage on-device models**, download and load a
   LiteRT model or import and load a GGUF model. Use Gemma 4 E2B or E4B Instruct
   for clients that send function tools.
2. Open **Settings → On-Device Inference → Local API**, choose a port (default **8000**),
   and tap **Start server**.
3. Copy the base URL, API key, and model ID into the client. On the same phone,
   use `http://127.0.0.1:8000/v1` with the port displayed in LocalMind.

For **BeeCount**, create a custom OpenAI-compatible provider and paste the base
URL (including `/v1`), API key, and model ID into its text model settings. Choose
that provider for text or assistant requests. Function calls are returned to
BeeCount, which controls whether to run its own tools and send their results
back. Receipt images and audio are outside the current API.

### Another device

Enable **Allow other devices on the local network** before starting. Connect
the client device to the same trusted network and use one of the LAN base URLs
shown in LocalMind. HTTP sends the API key and prompts without encryption.
Keep this listener on a trusted network and avoid port forwarding. Rotate
the key from Local API to revoke the previous key.

### Check the connection

Run these from the client host after replacing the placeholders. For same-phone
tests, run from an Android terminal app. For LAN tests, use the LAN base URL.

```sh
base_url='http://PHONE_IP:8000/v1'
read -rs api_key
curl -fsS "$base_url/models" -H "Authorization: Bearer $api_key"
curl -fsS "$base_url/chat/completions" \
  -H "Authorization: Bearer $api_key" \
  -H 'Content-Type: application/json' \
  -d '{"model":"MODEL_ID","messages":[{"role":"user","content":"Say hello."}]}'
unset api_key
```

Set `"stream": true` for SSE. The API supports a single choice, text messages,
and `tool_choice` of `auto` or `none` on supported models. Send the complete
message history with each request. GGUF accepts `temperature`, `top_p` and
`max_tokens`. LiteRT uses the loaded model's settings; it accepts
`temperature` for client compatibility and does not apply that hint.

Only one on-device generation can run at a time. If a request receives HTTP 429,
wait for the current generation to finish and try again. If there is no eligible
model loaded, load one in LocalMind and check the model ID again. If the port is
unavailable, stop the other listener or choose a different port.

Android shows a notification while the server runs. Stop it from that
notification or from **Local API**. The server may use more battery while
waiting for connections and stops when Android terminates LocalMind. It never
starts on its own.
