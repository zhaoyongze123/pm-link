package cn.iocoder.yudao.module.system.service.auth;

import cn.iocoder.yudao.module.system.controller.admin.auth.vo.AuthLoginRespVO;

import javax.servlet.http.HttpServletRequest;

public interface KodSsoService {

    String buildAuthorizeRedirectUrl(HttpServletRequest request, String redirectUri);

    AuthLoginRespVO loginByKodToken(String kodAccessToken);

    String buildClientRedirectUrl(String kodAccessToken, String redirectUri);

    AuthLoginRespVO exchangeCode(String code);

}
