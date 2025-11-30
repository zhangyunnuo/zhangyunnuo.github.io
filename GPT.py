from openai import OpenAI, api_key
import time
import json
import speech_recognition as sr

with open('user_data.json', 'r') as f:
    user_data = json.load(f)

API_KEY = user_data["api_key"]

# print(API_KEY) 测试

if API_KEY == 1:
    API_KEY = input("请输入你的API\n")
    with open('user_data.json', 'w') as f:
        user_data = {
            "api_key" : API_KEY
        }
        json.dump(user_data,f)

client = OpenAI(
    api_key = API_KEY,
    base_url = "https://api.chatanywhere.tech/v1"
)

def print_color(text, color):
    color_codes = {
        "black": "30", "red": "31", "green": "32", "yellow": "33", "blue": "34",
        "magenta": "35", "cyan": "36", "white": "37"
    }
    color_code = color_codes.get(color.lower(), "37")
    print(f"\033[{color_code}m{text}\033[0m", end="")

# 非流式响应
def gpt_35_api(messages: list):
    """为提供的对话消息创建新的回答

    Args:
        messages (list): 完整的对话消息
    """
    completion = client.chat.completions.create(model="gpt-3.5-turbo", messages=messages)
    print(completion.choices[0].message.content)
    return completion.choices[0].message  # 返回AI的回答以添加到对话历史中

def gpt_35_api_stream(messages: list):
    """为提供的对话消息创建新的回答 (流式传输)

    Args:
        messages (list): 完整的对话消息
    """
    stream = client.chat.completions.create(
        model='gpt-3.5-turbo',
        messages=messages,
        stream=True,
    )
    response_content = ""
    try:
        for chunk in stream:
            if chunk.choices[0].delta.content is not None:
                response_content += chunk.choices[0].delta.content
                print_color(chunk.choices[0].delta.content, "blue")
                #time.sleep(0.2)
        return {"role": "assistant", "content": response_content}  # 返回AI的回答以添加到对话历史中
    except IndexError:
        pass

if __name__ == '__main__':
    conversation_history = []  # 初始化对话历史
    recognizer = sr.Recognizer()

    while True:
        user_massage = ""
        user_massage = input()
        # 将用户的消息添加到对话历史中
        conversation_history.append({'role': 'user', 'content': user_massage})

        # 调用流式API并获取AI的回答
        response = gpt_35_api_stream(conversation_history)
        if response:
            conversation_history.append(response)  # 将AI的回答添加到对话历史中

        print()