# Weekly Wallet数据库接入

当前目录为数据库迁移，不是网页文件。只在你自己的 Supabase 项目的 SQL Editor 中执行 `001_zhoujian.sql`。创建用户账本表、按账号读取策略及事务性写入函数；匿名用户不能读取账目，登录用户只能读取自己的账目，写入函数使用登录身份并校验输入。

上线步骤：

1. 打开已有项目 https://supabase.com/dashboard/project/scaccfuchbjbnqnrlcub 。
2. 在项目的 SQL Editor 执行同目录的 `001_zhoujian.sql`。首次运行前检查脚本，使用新项目可避免与已有表冲突。
3. 在 Authentication 的用户列表中创建你自己的登录用户；应用使用邮箱和密码登录，不开放自助注册。创建用户时设置密码并确认邮箱；已有用户应为原账号设置密码，不要创建重复账号。无需把登录密码提供给网站作者。
4. 在 Authentication 的 URL 配置中将 Site URL 设置为 `https://wegius1031.github.io/finance/`，并把该网址加入允许的 Redirect URLs。
5. `finance/config.js` 已填入你提供的 Project URL 和公开 Publishable key。不要使用 `sb_secret_`、`service_role` 或数据库密码。
6. 合并网站代码，让 GitHub Pages 发布 `/finance/` 目录。
7. 用手机打开页面，输入自己的邮箱和密码登录。创建一笔测试记录，再用电脑登录同一邮箱验证同步。

Project URL 和公开密钥已配置。2026-10-09 的真实接口检查返回 PGRST205：schema cache 中尚无 zhoujian_ledgers 表。SQL 尚待在控制台执行，随后需验证数据库权限、跨设备读写、冲突处理及手机浏览器行为。

此仓库是 Hexo 生成后的静态产物。如果以后在本机执行 Hexo 完整重新生成/部署，请把 finance 目录保存在你的 Hexo 源项目 source/finance 中并设置复制策略，避免重新部署时丢失独立页面。
