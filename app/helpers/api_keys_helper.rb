module ApiKeysHelper
  # 通用安装提示词：动态嵌入用户 Key，供一键复制到 agent 工具（v1.1 优化版，见 .trae/documents/00_安装提示词_优化版_P1-14.md）
  def install_prompt(plain_key)
    if plain_key.blank?
      return "你的 Key 尚未生成明文，请点击上方「重新生成」获取完整 Key 后再复制此提示词。"
    end

    <<~TEXT
      请帮我安装 HOLDLE AI 投研助手：

      1. 配置 MCP 服务（名称 holdle-ai）：
         - 地址：https://ai.holdle.com/mcp
         - 请求头：X-HOLDLE-Key: #{plain_key}
         - 说明：#{plain_key} 是我的专属 Key，请原样填入，不要改动或省略
      2. 安装个股数据脚本（国内优先镜像）：
         - 优先：curl -L https://cdn.jsdelivr.net/gh/emilesu/holdle-data-skill@master/holdle_data.py -o holdle_data.py
         - 备用：git clone https://github.com/emilesu/holdle-data-skill.git（或 ghproxy 等国内代理）
         - 检查 python 依赖（baostock / tickflow / akshare / pandas），缺哪个装哪个
      3. 完成后告诉我结果，并给我 1 个提问示例——不要实际调用工具，避免消耗我的次数

      规则：这是付费服务，每次提问扣 1 次，如返回剩余次数请告知；只教方法、不荐股；我的 Key 仅用于本地配置，勿外传。
    TEXT
  end
end
