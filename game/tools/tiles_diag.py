"""Diagnose aigei set page DOM: what image attrs / lazy-load patterns exist."""
import subprocess, json, os, time, tempfile, sys

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
        return {"parse_err": str(e), "raw": out[:500]}


URL = sys.argv[1] if len(sys.argv) > 1 else "https://www.aigei.com/set/rpgyouxisucaiji_zhan.html"
print(f"open {URL}", flush=True)
print(ab("open", URL)[-140:], flush=True)
time.sleep(3)
# scroll to trigger lazy load
ab("eval", "window.scrollTo(0,document.body.scrollHeight); 'ok'")
time.sleep(2)
ab("eval", "window.scrollTo(0,0); 'ok'")
time.sleep(1)

JS = r"(()=>{var r={};r.title=document.title;r.imgs=document.querySelectorAll('img').length;r.allEls=document.getElementsByTagName('*').length;var attrs={};var imgs=document.querySelectorAll('img');for(var i=0;i<imgs.length&&i<40;i++){var a=imgs[i].attributes;for(var k=0;k<a.length;k++){attrs[a[k].name]=(attrs[a[k].name]||0)+1;}}r.imgAttrs=attrs;var samp=[];for(var i=0;i<imgs.length&&i<6;i++){samp.push(imgs[i].outerHTML.slice(0,260));}r.samples=samp;var dl=document.querySelectorAll('[data-original]').length;r.dataOriginal=dl;var enc=document.body.innerHTML.match(/aigei-image-encode-/g);r.encCount=enc?enc.length:0;return JSON.stringify(r);})()"
info = parse(ab("eval", JS))
print(json.dumps(info, ensure_ascii=False, indent=2)[:2500], flush=True)
