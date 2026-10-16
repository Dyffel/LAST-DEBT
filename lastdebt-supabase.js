// LAST DEBT v1.6: browser identity + secure Supabase RPC calls.
const LD_SUPABASE_URL = 'https://vcogjuqrhduaukzkabml.supabase.co';
const LD_SUPABASE_KEY = 'sb_publishable_40K-FNE9h8_IrBzdhXRj6g_3buY5Nzn';
let ldClientPromise;
async function ldClient() {
  if (!ldClientPromise) ldClientPromise = (async () => {
    if (!window.supabase?.createClient) throw Error('Supabase library did not load. Check your internet connection.');
    const client = window.supabase.createClient(LD_SUPABASE_URL, LD_SUPABASE_KEY, {auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:false}});
    let {data:{session},error}=await client.auth.getSession();
    if(error)throw error;
    if(!session){const r=await client.auth.signInAnonymously();if(r.error)throw r.error;}
    return client;
  })();
  return ldClientPromise;
}
async function ldRpc(fn,args){const client=await ldClient();const {data,error}=await client.rpc(fn,args);if(error)throw Error(error.message);return data;}
function ldMessage(error){return error?.message||String(error)}
