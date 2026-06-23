class SensitiveService
  # 校验文本，返回结果
  def self.check(text)
    if MessageBoard.has_sensitive?(text)
      { pass: false, msg: "留言内容包含违规词汇，请修改后重新提交" }
    else
      { pass: true }
    end
  end
end