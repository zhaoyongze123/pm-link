#!/usr/bin/env bash
set -euo pipefail

PLUGIN_BASE_DIR="${PLUGIN_BASE_DIR:-/root/deployments/kodbox/data/plugins}"

write_app() {
  local plugin_dir="$1"
  local class_name="$2"
  local target_file="${PLUGIN_BASE_DIR}/${plugin_dir}/app.php"

  python3 - "$class_name" "$target_file" <<'PY'
from pathlib import Path
import sys

class_name = sys.argv[1]
target_file = Path(sys.argv[2])

template = """<?php
class __CLASS_NAME__ extends PluginBase{
    function __construct(){
        parent::__construct();
    }
    public function regist(){
        $this->hookRegist(array(
            'user.commonJs.insert' => '__CLASS_NAME__.echoJs'
        ));
    }
    public function echoJs(){
        $this->echoFile('static/main.js');
    }
    public function index(){
        if (!KodUser::isLogin()) {
            show_tips('用户未登录');
        }
        $config = $this->getConfig();
        $entryUrl = trim((string)_get($config, 'entryUrl', ''));
        if (!$entryUrl) {
            show_tips('插件入口地址未配置');
        }

        $joiner = strpos($entryUrl, '?') === false ? '?' : '&';
        $redirectUri = $entryUrl . $joiner . '_pluginRefresh=' . time();
        $entryParts = parse_url($entryUrl);
        $scheme = _get($entryParts, 'scheme', 'https');
        $host = _get($entryParts, 'host', '');
        if (!$host) {
            show_tips('插件入口地址配置无效');
        }
        $port = isset($entryParts['port']) ? ':' . $entryParts['port'] : '';
        $kodAccessToken = Action('user.index')->accessToken();
        $directLoginUrl = $scheme . '://' . $host . $port
            . '/admin-api/system/auth/kod-sso/direct-login?kodAccessToken='
            . rawurlencode($kodAccessToken)
            . '&redirectUri=' . rawurlencode($redirectUri);
        header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
        header('Pragma: no-cache');
        header('Location: ' . $directLoginUrl);
        exit;
    }
}
"""

target_file.write_text(template.replace('__CLASS_NAME__', class_name))
PY

  echo "[完成] 已写入 ${target_file}"
}

write_main() {
  local plugin_dir="$1"
  local page_id="$2"
  local icon="$3"
  local target_file="${PLUGIN_BASE_DIR}/${plugin_dir}/static/main.js"

  python3 - "$plugin_dir" "$page_id" "$icon" "$target_file" <<'PY'
from pathlib import Path
import sys

plugin_dir = sys.argv[1]
page_id = sys.argv[2]
icon = sys.argv[3]
target_file = Path(sys.argv[4])

template = """kodReady.push(function(){
    var pageId = '__PAGE_ID__';
    var pageTitle = '{{package.name}}';
    var pluginUrl = '/index.php?plugin/__PLUGIN_DIR__/index';

    function buildFreshUrl() {
        return pluginUrl + '&_pluginRefresh=' + Date.now();
    }

    Events.bind('main.menu.loadBefore', function(listData){
        listData[pageId] = {
            name: pageTitle,
            url: pluginUrl,
            target: '{{config.openWith}}',
            subMenu: '{{config.menuSubMenu}}',
            menuAdd: '{{config.menuAdd}}',
            icon: '__ICON__'
        };
    });

    Router.mapIframe({
        page: pageId,
        title: pageTitle,
        url: buildFreshUrl(),
        ignoreLogin: false
    });
});
"""

content = template.replace('__PLUGIN_DIR__', plugin_dir).replace('__PAGE_ID__', page_id).replace('__ICON__', icon)
target_file.write_text(content)
PY

  echo "[完成] 已写入 ${target_file}"
}

write_app "approvalCreateCenter" "approvalCreateCenterPlugin"
write_main "approvalCreateCenter" "{{package.id}}" "ri-draft-fill"

write_app "meetingRoom" "meetingRoomPlugin"
write_main "meetingRoom" "{{package.id}}" "ri-team-fill"

write_app "scheduleCenter" "scheduleCenterPlugin"
write_main "scheduleCenter" "{{package.id}}" "ri-calendar-check-fill"

write_app "partyFile" "partyFilePlugin"
write_main "partyFile" "partyFileStandaloneV2" "ri-government-fill"
