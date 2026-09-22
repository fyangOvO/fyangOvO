"""Search aigei and harvest /set/ collection links + basic page diagnostics."""
import subprocess, json, os, time, tempfile, sys, urllib.parse

AB_EXE = r"C:\Users\11265\.workbuddy\binaries\node\versions\22.22.2\node_modules\agent-browser\bin\agent-browser-win32-x64.exe"
env = os.environ.copy()
env["PATH"] = r"C:\Users\11265\.workbuddy\binaries\node\versions\22.22.2" + os.pathsep + env.get("PATH", "")


def ab(*args, timeout=120):
    fo, fe = tempfile.TemporaryFile(), tempfile.TemporaryFile()
    try:
        subprocess.run([AB_EXE] + list(args), stdout=fo, stderr=fe,
                       stdin=subprocess.DEVNULL, env=env, timeout=timeout, cwd=r"D:\七傳說")
        fo.seek(0)
        return fo.read().decode("utf-8", errors="replace")
    except Exception as e:
        return f"ERR {e}"
    finally:
        fo.close(); fe.close()


def parse(out):
    out = out.strip()
    try:
        j = json.loads(out)
        return json.loads(j) if isinstance(j, str) else j
    except Exception as e:
        return {"parse_err": str(e), "raw": out[:400]}


HARVEST_JS = r"(()=>{var r={};r.title=document.title;var as=document.querySelectorAll('a[href]');var sets=[];var seen={};for(var i=0;i<as.length;i++){var h=as[i].href||'';if(h.indexOf('/set/')<0)continue;if(seen[h])continue;seen[h]=1;var t=(as[i].textContent||'').trim().slice(0,50);sets.push({url:h,text:t});}r.sets=sets.slice(0,60);r.setCount=sets.length;r.imgs=document.querySelectorAll('img').length;r.enc=(document.body.innerHTML.match(/aigei-image-encode-/g)||[]).length;r.dataOrig=document.querySelectorAll('[data-original]').length;return JSON.stringify(r);})()"

queries = sys.argv[1:] or ["像素地图瓦片"]
for q in queries:
    url = "https://www.aigei.com/s?type=game&q=" + urllib.parse.quote(q)
    print(f"\n===== QUERY: {q} =====", flush=True)
    print(f"URL: {url}", flush=True)
    print(ab("open", url)[-120:].replace("\n", " "), flush=True)
    time.sleep(4)
    ab("eval", "window.scrollTo(0,document.body.scrollHeight); 'ok'")
    time.sleep(2)
    info = parse(ab("eval", HARVEST_JS))
    if "parse_err" in info:
        print("PARSE FAIL:", info, flush=True)
        continue
    print(f"title={info.get('title')}", flush=True)
    print(f"imgs={info.get('imgs')} dataOrig={info.get('dataOrig')} encCount={info.get('enc')} setLinks={info.get('setCount')}", flush=True)
    for s in info.get("sets", [])[:30]:
        print(f"  {s['url']}   | {s['text']}", flush=True)
