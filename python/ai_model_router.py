# DRAFT / PoC. Never tested.
import os
import json
from ollama import Client as OllamaClient
from anthropic import Anthropic
from pydantic import BaseModel

# 1. Initialize our clients
ollama_client = OllamaClient(host='http://localhost:11434')
# Ensure your ANTHROPIC_API_KEY environment variable is set
anthropic_client = Anthropic()

# Define the structured output format we want from Gemma
class LocalResponse(BaseModel):
    can_answer_reliably: bool
    answer: str
    reason_if_failed: str

def process_with_fallback(user_prompt: str):
    print(f"🤖 Step 1: Asking local Gemma 4...")

    system_instruction = (
        "You are a local triage assistant. If the user's request involves highly complex coding, "
        "deep logic, or advanced reasoning beyond your certain knowledge, set 'can_answer_reliably' to false. "
        "Otherwise, answer the prompt fully and set 'can_answer_reliably' to true."
    )

    try:
        # 2. Try the local Gemma 4 model first using Structured Outputs
        response = ollama_client.chat(
            model='gemma4:e4b',
            messages=[
                {"role": "system", "content": system_instruction},
                {"role": "user", "content": user_prompt}
            ],
            format=LocalResponse.model_json_schema()
        )

        # Parse the local JSON response
        result = LocalResponse.model_validate_json(response['message']['content'])

        # 3. Check if Gemma succeeded
        if result.can_answer_reliably:
            print("✅ Gemma 4 handled it locally!")
            return result.answer
        else:
            print(f"⚠️ Gemma passed. Reason: {result.reason_if_failed}")

    except Exception as e:
        print(f"💥 Local model error or timeout: {e}. Falling back to cloud automatically.")

    # 4. Fallback Step: Escalating to Claude in the cloud
    print("☁️ Step 2: Escalating task to Claude...")
    claude_response = anthropic_client.messages.create(
        model="claude-3-5-sonnet-latest",
        max_tokens=2048,
        messages=[
            {"role": "user", "content": user_prompt}
        ]
    )
    print("✨ Claude provided the solution.")
    return claude_response.content[0].text

# --- Example Usage ---
# Example 1: Something Gemma can easily do locally
prompt_easy = "Write a basic python script to calculate the area of a circle."
print(process_with_fallback(prompt_easy))

print("\n" + "="*40 + "\n")

# Example 2: Something complex that will trigger the cloud fallback
prompt_hard = "Design a highly optimized, concurrent multi-producer multi-consumer ring buffer in C++ using memory barriers and zero locks."
print(process_with_fallback(prompt_hard))
