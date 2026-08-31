# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

## 百度搜索资源平台「主动推送」环境变量

在 `.env`（开发）和 `.env.production`（生产）中配置，`token` 从百度站长平台（ziyuan.baidu.com）复制填入，**不要写进 git**：

- `BAIDU_PUSH_SITE`：站点域名，如 `www.holdle.com`
- `BAIDU_PUSH_TOKEN`：主动推送 API token；留空则自动跳过推送（业务不受影响）

功能说明：股票财务数据真实变更或新收录股票时，异步推送对应详情页 URL 给百度。不推送历史存量 URL。

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...
