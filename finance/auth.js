let supabaseClient=null;
const authNotice=message=>{document.getElementById('auth-notice').textContent=message};
const config=window.ZHOUJIAN_CONFIG||{};
const looksSecret=key=>key.startsWith('sb_secret_')||(()=>{try{return JSON.parse(atob(key.split('.')[1])).role==='service_role'}catch{return false}})();
async function startWallet(session){
  if(!session?.user)return;
  document.getElementById('auth-panel').hidden=true;
  const root=document.getElementById('wallet-root');root.hidden=false;root.dataset.userId=session.user.id;
  if(root.dataset.started)return;root.dataset.started='true';
  const script=document.createElement('script');script.src='./wallet.js';script.type='module';script.onerror=()=>authNotice('记账页面加载失败，请刷新重试');document.body.appendChild(script);
}
async function initAuth(){
  if(!config.supabaseUrl||!config.publishableKey){authNotice('数据库尚未配置，当前页面不能保存账目。请先创建 Supabase 项目并填写 config.js。');document.querySelectorAll('#auth-panel input,#auth-panel button').forEach(el=>el.disabled=true);return}
  let url;try{url=new URL(config.supabaseUrl)}catch{authNotice('Supabase 项目地址格式不正确');return}
  if(url.protocol!=='https:'||looksSecret(config.publishableKey)){authNotice('连接配置无效。这里只能使用 HTTPS 项目地址和公开 Publishable / anon key。');return}
  if(!window.supabase){authNotice('登录组件加载失败，请检查网络后刷新页面');return}
  supabaseClient=window.supabase.createClient(config.supabaseUrl,config.publishableKey,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
  window.zhoujianSupabase=supabaseClient;
  const {data,error}=await supabaseClient.auth.getSession();if(error){authNotice('登录状态读取失败，请重试');return}if(data.session)await startWallet(data.session);
  supabaseClient.auth.onAuthStateChange((event,session)=>{if(event==='SIGNED_IN'&&session)setTimeout(()=>void startWallet(session),0);if(event==='SIGNED_OUT')location.reload()});
  document.getElementById('login-form').onsubmit=async e=>{e.preventDefault();const email=document.getElementById('email').value.trim(),button=document.getElementById('send-link');button.disabled=true;authNotice('正在发送登录邮件…');try{const {error}=await supabaseClient.auth.signInWithOtp({email,options:{emailRedirectTo:location.origin+location.pathname,shouldCreateUser:false}});authNotice(error?'登录邮件发送失败。请确认该邮箱已添加到 Supabase 用户列表，并稍后重试。':'登录邮件已发送，请在当前设备打开邮件里的链接。')}catch{authNotice('网络连接失败，请重试')}finally{button.disabled=false}};
}
void initAuth().catch(()=>authNotice('连接失败，请检查网络后刷新页面'));
