class PagesController < ApplicationController
  def join
  end

  def video
  end

  def about
    # 关于 HOLDLE 页：正文为静态 Markdown（app/views/pages/about.md）
    @about_markdown = File.read(Rails.root.join("app/views/pages/about.md"))
  end
end
