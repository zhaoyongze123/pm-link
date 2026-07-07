#!/usr/bin/env bash
set -euo pipefail

PLUGIN_BASE_DIR="${PLUGIN_BASE_DIR:-/root/deployments/kodbox/data/plugins}"

write_plugin() {
  local plugin_dir="$1"
  local page_id="$2"
  local icon="$3"
  local target_file="${PLUGIN_BASE_DIR}/${plugin_dir}/static/main.js"

  if [ ! -d "${PLUGIN_BASE_DIR}/${plugin_dir}" ]; then
    echo "[错误] 插件目录不存在: ${PLUGIN_BASE_DIR}/${plugin_dir}" >&2
    exit 1
  fi

  python3 - "${page_id}" "${icon}" "${target_file}" <<'PY'
from pathlib import Path
import sys

page_id = sys.argv[1]
icon = sys.argv[2]
target_file = Path(sys.argv[3])

template = """kodReady.push(function(){
    var pageId = '__PAGE_ID__';
    var pageTitle = '{{package.name}}';
    var pageUrl = '{{config.entryUrl}}';
    var directLoginPath = '/admin-api/system/auth/kod-sso/direct-login';

    function buildFreshUrl() {
        var joiner = pageUrl.indexOf('?') >= 0 ? '&' : '?';
        return pageUrl + joiner + '_pluginRefresh=' + Date.now();
    }

    function buildDirectLoginUrl(kodAccessToken, redirectUrl) {
        return window.location.origin + directLoginPath
            + '?kodAccessToken=' + encodeURIComponent(kodAccessToken)
            + '&redirectUri=' + encodeURIComponent(redirectUrl);
    }

    function extractKodAccessToken(result) {
        if (!result || result.code !== true || !result.data || typeof result.data !== 'string') {
            var message = result && (result.info || result.data || result.msg);
            throw new Error(message || '获取可道云登录票据失败');
        }
        return result.data;
    }

    function requestKodAccessToken() {
        return $.ajax({
            url: '/index.php?user/index/accessTokenGet',
            method: 'GET',
            dataType: 'json'
        });
    }

    function escapeHtml(text) {
        return String(text || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    var OaEntryView = ClassBase.extend({
        init: function() {
            this.$el = this.parent.$('.app-main');
            this.$el.css({
                width: '100%',
                height: '100%',
                background: '#fff'
            });
            this.$el.html('');
            this.openIframe();
        },
        openIframe: function() {
            var self = this;
            requestKodAccessToken().done(function(result){
                try {
                    var kodAccessToken = extractKodAccessToken(result);
                    var iframeUrl = buildDirectLoginUrl(kodAccessToken, buildFreshUrl());
                    var iframeHtml = '<iframe'
                        + ' src="' + iframeUrl + '"'
                        + ' style="width:100%;height:100%;border:none;background:#fff;"'
                        + ' referrerpolicy="same-origin"'
                        + '></iframe>';
                    self.$el.html(iframeHtml);
                } catch (error) {
                    self.renderError(error && error.message ? error.message : '打开页面失败，请刷新后重试');
                }
            }).fail(function(xhr){
                var response = xhr && xhr.responseJSON;
                var message = response && (response.info || response.data || response.msg);
                self.renderError(message || '获取可道云登录票据失败');
            });
        },
        renderError: function(message) {
            this.$el.html(
                '<div style="box-sizing:border-box;width:100%;height:100%;padding:32px;background:#fff;color:#333;line-height:1.8;">'
                + '<div style="font-size:16px;font-weight:600;margin-bottom:8px;">打开失败</div>'
                + '<div style="font-size:14px;">' + escapeHtml(message) + '</div>'
                + '</div>'
            );
        }
    });

    Events.bind('main.menu.loadBefore', function(listData){
        listData[pageId] = {
            name: pageTitle,
            url: pageUrl,
            target: '{{config.openWith}}',
            subMenu: '{{config.menuSubMenu}}',
            menuAdd: '{{config.menuAdd}}',
            icon: '__ICON__'
        };
    });

    Router.mapPage({
        page: pageId,
        title: pageTitle,
        View: OaEntryView
    });
});
"""

content = template.replace("__PAGE_ID__", page_id).replace("__ICON__", icon)
target_file.write_text(content)
PY

  echo "[完成] 已写入 ${target_file}"
}

write_plugin "approvalCreateCenter" "{{package.id}}" "ri-draft-fill"
write_plugin "meetingRoom" "{{package.id}}" "ri-team-fill"
write_plugin "scheduleCenter" "{{package.id}}" "ri-calendar-check-fill"
write_plugin "partyFile" "partyFileStandaloneV2" "ri-government-fill"
