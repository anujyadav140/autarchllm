# Autarch LLM

Autarch is an Ollama compatabile, flutter web, android and windows app for working with privately hosted models such as Llama 2, Mistral, Gemini and more. It's essentially ChatGPT app UI that connects to your private models hosted through ngrok/localhost. 

## Getting Started

1. Downlaod Ollama https://ollama.com/download/windows
2. Download ngrok https://download.ngrok.com/windows
3. Ollama can be accessed using ngrok with the following command line: ngrok http 11434 --host-header="localhost:11434"
4. Go to the Autarch LLM app and find the settings button
5. Change the Ollama Serve Uri textfield to your ngrok url
6. You are good to go!
