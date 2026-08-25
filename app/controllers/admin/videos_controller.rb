module Admin
  class VideosController < BaseController
    before_action :set_video, only: [:edit, :update, :destroy]

    def index
      @videos = Video.sorted
    end

    def new
      @video = Video.new
    end

    def create
      @video = Video.new(video_params)
      @video.published_at ||= Time.current if @video.is_published
      if @video.save
        redirect_to admin_videos_path, notice: "视频创建成功"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      @video.assign_attributes(video_params)
      @video.published_at ||= Time.current if @video.is_published
      if @video.save
        redirect_to admin_videos_path, notice: "视频更新成功"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @video.destroy
      redirect_to admin_videos_path, notice: "视频已删除"
    end

    private

    def set_video
      @video = Video.find(params[:id])
    end

    def video_params
      params.require(:video).permit(:title, :cover_url, :bilibili_url, :youtube_url, :is_published, :sort, :published_at)
    end
  end
end
