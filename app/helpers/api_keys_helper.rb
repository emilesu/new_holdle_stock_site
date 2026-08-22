module ApiKeysHelper
  # 通用安装提示词：动态嵌入用户 Key，供一键复制到 agent 工具
  def install_prompt(plain_key)
    if plain_key.blank?
      return "你的 Key 尚未生成明文，请点击上方「重新生成」获取完整 Key 后再复制此提示词。"
    end

    <<~TEXT
      请帮我在当前 AI 工具中安装配置 HOLDLE AI 投研助手 MCP 服务：

      服务名称：holdle
      服务地址：https://www.holdle.com/api/v1/mcp
      API Key：#{plain_key}
      认证方式：请求头 Authorization: Bearer #{plain_key}

      配置要求：
      1. 该 MCP 提供 precheck / confirm / release 三个工具，用于提问计费
      2. 调用时请把用户的问题原文作为 question 参数传入
      3. 不要向用户展示完整 Key

      配置完成后告诉我「已配置完成」。
    TEXT
  end
end
