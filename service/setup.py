"""Guided local Docker configuration. Never installs Docker or changes DNS/firewalls."""
import argparse
import os
from pathlib import Path
import re
import secrets
import shlex
import shutil
import subprocess
import sys
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent

def origin(value):
    parts = urlsplit(value)
    if parts.scheme != 'https' or not parts.hostname or parts.username or parts.password or parts.path not in ('','/') or parts.query or parts.fragment or re.search(r'[\s$`\\"\'<>]',value):
        raise ValueError('域名必须是完整 HTTPS 源站，例如 https://reports.example.com，不含路径或凭据。')
    try:
        parts.port
        parts.hostname.encode('ascii')
    except (ValueError,UnicodeError):
        raise ValueError('请使用有效 ASCII/Punycode 域名和端口。') from None
    return value.rstrip('/')

def port(value):
    number=int(value)
    if not 1024 <= number <= 65535:
        raise ValueError('本地端口须为 1024–65535。')
    return str(number)

def private_read(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError(f'{path.name} 不是普通文件；拒绝读取或覆盖。')
    if path.stat().st_uid != os.getuid():
        raise ValueError(f'{path.name} 不属于当前用户；拒绝读取。')
    os.chmod(path,0o600)
    return path.read_text()

def private_create(path,text):
    flags=os.O_WRONLY|os.O_CREAT|os.O_EXCL
    if hasattr(os,'O_NOFOLLOW'): flags|=os.O_NOFOLLOW
    descriptor=os.open(path,flags,0o600)
    with os.fdopen(descriptor,'w') as stream:
        stream.write(text)

def configure(root,url=None,local_port=None):
    config_path=root/'.env'
    if config_path.exists() or config_path.is_symlink():
        text=private_read(config_path)
        values={}
        for line in text.splitlines():
            if not line.strip() or line.lstrip().startswith('#'): continue
            if '=' not in line: raise ValueError('已有 .env 格式无法安全解析，请手动检查；未覆盖。')
            name,value=line.split('=',1)
            if name in values: raise ValueError('已有 .env 包含重复设置；未覆盖。')
            values[name]=value
        saved_url=origin(values.get('PUBLIC_BASE_URL',''))
        saved_port=port(values.get('LOCAL_PORT','8080'))
        key=values.get('REPORT_UPLOAD_KEY','')
        if not re.fullmatch(r'[A-Za-z0-9_-]{32,256}',key):
            raise ValueError('已有 .env 密钥不是可自动处理的未加引号 URL-safe 格式；请手动配置，未覆盖。')
        if url and origin(url)!=saved_url or local_port and port(local_port)!=saved_port:
            raise ValueError('已有域名/端口与参数不同；为保护设置未覆盖，请显式编辑 .env 和 client.env。')
        url,local_port=saved_url,saved_port
    else:
        if not url:
            if not sys.stdin.isatty(): raise ValueError('非交互环境请提供 --url https://你的域名。')
            url=input('你的报告 HTTPS 域名（例如 https://reports.example.com）：').strip()
        url=origin(url)
        local_port=port(local_port or '8080')
        key=secrets.token_urlsafe(32)
        values={'PUBLIC_BASE_URL':url,'REPORT_UPLOAD_KEY':key,'LOCAL_PORT':local_port}
        private_create(config_path,''.join(name+'='+value+'\n' for name,value in values.items()))
    client=root/'client.env'
    content='# 私密上传凭据；不要分享、提交或放入日志。\nexport NQ_UPLOAD_KEY='+shlex.quote(key)+'\nexport NQ_UPLOAD_URL='+shlex.quote(url+'/api/v1/reports')+'\n'
    if client.exists() or client.is_symlink():
        if private_read(client)!=content:
            raise ValueError('已有 client.env 内容不同；未覆盖，请手动核对配置。')
    else:
        private_create(client,content)
    return values,url,local_port,client

def main(argv=None,root=ROOT):
    parser=argparse.ArgumentParser(description='一键准备/启动 NodeQuality Docker 报告服务（不自动安装 Docker）')
    parser.add_argument('--url',help='你的 HTTPS 源站，例 https://reports.example.com')
    parser.add_argument('--port',help='仅绑定 localhost 的主机端口，默认8080')
    group=parser.add_mutually_exclusive_group()
    group.add_argument('--yes',action='store_true',help='明确授权在本机执行 docker compose up -d --build')
    group.add_argument('--configure-only',action='store_true',help='仅生成私密配置，不启动 Docker')
    args=parser.parse_args(argv)
    os.umask(0o077)
    try:
        if not args.configure_only:
            if not shutil.which('docker'):
                raise ValueError('未找到 Docker。请先安装 Docker Engine + Compose 插件；或用 --configure-only 仅生成配置。')
            subprocess.run(['docker','compose','version'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        values,url,local_port,client=configure(root,args.url,args.port)
        print(f'配置已保存/复用，权限0600；未显示上传密钥。\n报告地址：{url}\n本机反代目标：http://127.0.0.1:{local_port}')
        print('域名/DNS、TLS 证书及反向代理需自行准备；本命令不会修改网络或防火墙。')
        if not args.configure_only:
            approved=args.yes
            if not approved and sys.stdin.isatty():
                approved=input('将在本机构建并启动容器，可能下载基础镜像/依赖。输入 START 继续：').strip()=='START'
            if not approved:
                print('尚未启动容器；配置保留。确认后重新运行并输入 START，或显式加 --yes。')
                return 0
            environment=os.environ.copy()
            for name in ('PUBLIC_BASE_URL','REPORT_UPLOAD_KEY','LOCAL_PORT','RETENTION_DAYS','MAX_UPLOAD_BYTES','MAX_REPORTS','UPLOADS_PER_HOUR','COMPOSE_FILE','COMPOSE_PROFILES','COMPOSE_PROJECT_NAME'):
                environment.pop(name,None)
            subprocess.run(['docker','compose','-f',str(root/'compose.yaml'),'--project-directory',str(root),'--env-file',str(root/'.env'),'up','-d','--build'],check=True,env=environment,cwd=root)
            print('Docker Compose 命令成功；公网 DNS/TLS/反代可达性仍需部署者验证。')
        print('CLI 配置（在运行测试的机器上安全保存此私密文件；不要粘贴其内容）：')
        print('  bash setup.sh run --config '+shlex.quote(str(client)))
        print('注意：上传为原始报告，无自动脱敏；必须先审阅敏感内容。未加上传参数时仍仅本地保存。')
        return 0
    except (ValueError,OSError,subprocess.CalledProcessError) as error:
        # Do not expose environment, subprocess arguments with secrets, or existing config contents.
        print('配置未完成：'+str(error),file=sys.stderr)
        return 1

if __name__=='__main__':
    raise SystemExit(main())
