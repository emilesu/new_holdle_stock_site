class PagesController < ApplicationController
  def join
  end

  def plans
  end

  def video
    @videos = Video.published.sorted
  end

  def about
    # TODO: 「关于 HOLDLE」页面暂时下线（改版中），直接访问重定向回首页。
    # 改版完成后恢复下方原有逻辑即可。
    redirect_to root_path and return

    # 关于 HOLDLE 页：正文为静态 Markdown（app/views/pages/about.md）
    # @about_markdown = File.read(Rails.root.join("app/views/pages/about.md"))
  end
end
