# 周见数据库接入

当前目录为数据库迁移，不是网页文件。只在你自己的 Supabase 项目的 SQL Editor 中执行 `001_zhoujian.sql`。创建用户账本表、按账号读取策略及事务性写入函数；匿名用户不能读取账目，登录用户只能读取自己的账目，写入函数使用登录身份并校验输入。

上线步骤：

1. 在 https://supabase.com/dashboard 注册并创建一个项目，保存数据库密码，不要把密码写入网站。
2. 在项目的 SQL Editor 执行同目录的 `001_zhoujian.sql`。首次运行前检查脚本，使用新项目可避免与已有表冲突。
3. 在 Authentication 的用户列表中创建你自己的登录用户；当前应用仅向已有用户发送登录邮件，不开放自助注册。无需把登录密码提供给网站作者。
4. 在 Authentication 的 URL 配置中将 Site URL 设置为 `https://wegius1031.github.io/finance/`，并把该网址加入允许的 Redirect URLs。
5. 找到 Project URL 和公开的 Publishable key（旧项目可使用 anon key），填入 `finance/config.js`。不要使用 `sb_secret_`、`service_role` 或数据库密码。
6. 合并网站代码，让 GitHub Pages 发布 `/finance/` 目录。
7. 用手机打开页面，输入自己的邮箱，打开同一设备上收到的登录链接。创建一笔测试记录，再用电脑登录同一邮箱验证同步。

目前 config.js 没有配置真实项目，页面会显示未配置提示并禁用登录。SQL 脚本未在真实 Supabase 数据库中运行；接入后仍需验证数据库权限、跨设备读写、冲突处理及手机浏览器行为。

此仓库是 Hexo 生成后的静态产物。如果以后在本机执行 Hexo 完整重新生成/部署，请把 finance 目录保存在你的 Hexo 源项目 source/finance 中并设置复制策略，避免重新部署时丢失独立页面。
