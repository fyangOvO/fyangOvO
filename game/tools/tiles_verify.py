"""Step 1: verify the aigei extraction toolchain end-to-end on one page.

Uses temp-file redirection instead of capture_output pipes: agent-browser
spawns a persistent daemon/browser that inherits stdout, which makes
subprocess.run(..., capture_output=True) block forever waiting for EOF.
"""
import subprocess
import json
import os
import base64
import time
import tempfile

AB_EXE = r"C:\Users\11265\.workbuddy\binaries\node\versions\22.22.2\node_modules\agent-browser\bin\agent-browser-win32-x64.exe"
env = os.environ.copy()
env["PATH"] = r"C:\Users\11265\.workbuddy\binaries\node\versions\22.22.2" + os.pathsep + env.get("PATH", "")


def ab(*args, timeout=120):
    fo = tempfile.TemporaryFile()
    fe = tempfile.TemporaryFile()
    try:
        r = subprocess.run([AB_EXE] + list(args), stdout=fo, stderr=fe,
                           stdin=subprocess.DEVNULL, env=env, timeout=timeout,
                           cwd=r"D:\七傳說")
        fo.seek(0)
        return fo.read().decode("utf-8", errors="replace")
    except Exception as e:
        return f"ERR {e}"
    finally:
        fo.close()
        fe.close()


PROBE_JS = r"(async()=>{try{var all=document.querySelectorAll('[data-original]');var thumbs=0,full=0,sampleFull='';for(var i=0;i<all.length;i++){var v=all[i].getAttribute('data-original')||'';if(!v.startsWith('aigei-image-encode-'))continue;var b=v.slice('aigei-image-encode-'.length);var u;try{u=decodeURIComponent(escape(atob(b)));}catch(e){continue;}if(u.includes('imageMogr2')){thumbs++;}else{full++;if(!sampleFull)sampleFull=u;}}return JSON.stringify({total:all.length,thumbs,full,sampleFull:sampleFull.slice(0,180)});}catch(e){return JSON.stringify({err:e.message});}})()"

EXTRACT_JS = r"(async()=>{try{var seen={};var items=[];var all=document.querySelectorAll('[data-original]');for(var i=0;i<all.length;i++){var v=all[i].getAttribute('data-original')||'';if(!v.startsWith('aigei-image-encode-'))continue;var b=v.slice('aigei-image-encode-'.length);var url;try{url=decodeURIComponent(escape(atob(b)));}catch(e){continue;}if(url.includes('imageMogr2'))continue;if(seen[url])continue;seen[url]=1;if(items.length>=3)continue;var r=await fetch(url);var buf=await r.arrayBuffer();var dt=btoa(String.fromCharCode.apply(null,new Uint8Array(buf)));var ext=(url.match(/\.(png|jpg|gif|jpeg)/i)||['','png'])[1].toLowerCase();items.push({url:url.slice(0,200),ext:ext,size:buf.byteLength,b64:dt});}return JSON.stringify({count:items.length,items:items});}catch(e){return JSON.stringify({err:e.message});}})()"


def parse(out):
    out = out.strip()
    try:
        j = json.loads(out)
        return json.loads(j) if isinstance(j, str) else j
    except Exception as e:
        return {"parse_err": str(e), "raw": out[:300]}


TEST_URL = "https://www.aigei.com/set/rpgyouxisucaiji_zhan.html"

print(f"Opening {TEST_URL}", flush=True)
o = ab("open", TEST_URL)
print("open ->", o[-160:].replace("\n", " "), flush=True)
time.sleep(2)

print("\n[1] PROBE (count thumbs vs full-res)", flush=True)
info = parse(ab("eval", PROBE_JS))
print(json.dumps(info, ensure_ascii=False, indent=2)[:600], flush=True)

print("\n[2] EXTRACT (fetch up to 3 real images as bytes)", flush=True)
data = parse(ab("eval", EXTRACT_JS, timeout=180))
if "err" in data or "parse_err" in data:
    print("EXTRACT FAIL:", json.dumps(data, ensure_ascii=False)[:400], flush=True)
else:
    print(f"count={data.get('count')}", flush=True)
    for it in data.get("items", []):
        raw = base64.b64decode(it["b64"])
        print(f"  size={it['size']:>7} bytes  ext={it['ext']}  magic={raw[:8].hex()}  url={it['url'][:110]}", flush=True)
    print("\nTOOLCHAIN OK" if data.get("count", 0) > 0 else "\nNO IMAGES RETURNED", flush=True)
