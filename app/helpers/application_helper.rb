module ApplicationHelper
  def user_avatar_tag(user, css_class: "", size: nil)
    size_css = size || "w-10 h-10"

    if user.avatar.present?
      tag.img(
        src: user.avatar,
        alt: user.nickname.presence || "avatar",
        class: "#{size_css} rounded object-cover shrink-0 #{css_class}",
        onerror: "this.onerror=null;this.style.display='none';this.nextElementSibling.style.display='flex'"
      ) + tag.div(
        user.avatar_char,
        class: "#{size_css} rounded bg-link flex items-center justify-center text-white font-bold shrink-0 #{css_class}",
        style: "display:none"
      )
    else
      tag.div(
        user.avatar_char,
        class: "#{size_css} rounded bg-link flex items-center justify-center text-white font-bold shrink-0 #{css_class}"
      )
    end
  end
end
