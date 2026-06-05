package cn.iocoder.yudao.module.system.service.auth;

import cn.hutool.core.lang.UUID;
import cn.hutool.core.collection.CollUtil;
import cn.hutool.core.util.IdUtil;
import cn.hutool.core.util.ObjectUtil;
import cn.hutool.core.util.StrUtil;
import cn.iocoder.yudao.framework.common.enums.CommonStatusEnum;
import cn.iocoder.yudao.framework.common.enums.UserTypeEnum;
import cn.iocoder.yudao.framework.common.util.http.HttpUtils;
import cn.iocoder.yudao.framework.common.util.json.JsonUtils;
import cn.iocoder.yudao.framework.common.util.servlet.ServletUtils;
import cn.iocoder.yudao.framework.security.core.LoginUser;
import cn.iocoder.yudao.framework.security.core.util.SecurityFrameworkUtils;
import cn.iocoder.yudao.framework.web.core.util.WebFrameworkUtils;
import cn.iocoder.yudao.module.system.controller.admin.auth.vo.AuthLoginRespVO;
import cn.iocoder.yudao.module.system.controller.admin.user.vo.user.UserSaveReqVO;
import cn.iocoder.yudao.module.system.dal.dataobject.auth.KodSsoUserBindDO;
import cn.iocoder.yudao.module.system.dal.dataobject.dept.DeptDO;
import cn.iocoder.yudao.module.system.dal.dataobject.user.AdminUserDO;
import cn.iocoder.yudao.module.system.dal.mysql.auth.KodSsoUserBindMapper;
import cn.iocoder.yudao.module.system.enums.logger.LoginLogTypeEnum;
import cn.iocoder.yudao.module.system.framework.kodsso.config.KodSsoProperties;
import cn.iocoder.yudao.module.system.service.dept.DeptService;
import cn.iocoder.yudao.module.system.service.permission.PermissionService;
import cn.iocoder.yudao.module.system.service.user.AdminUserService;
import com.fasterxml.jackson.databind.JsonNode;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.validation.annotation.Validated;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import java.time.LocalDateTime;
import java.util.Collections;
import java.util.HashSet;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Supplier;

import static cn.iocoder.yudao.framework.common.exception.util.ServiceExceptionUtil.exception;
import static cn.iocoder.yudao.module.system.enums.ErrorCodeConstants.*;

@Service
@Validated
@Slf4j
public class KodSsoServiceImpl implements KodSsoService {

    private static final String EXCHANGE_CODE_PARAM = "kodSsoCode";

    @Resource
    private KodSsoProperties kodSsoProperties;
    @Resource
    private KodSsoUserBindMapper kodSsoUserBindMapper;
    @Resource
    private AdminUserService adminUserService;
    @Resource
    private AdminAuthService adminAuthService;
    @Resource
    private PermissionService permissionService;
    @Resource
    private DeptService deptService;

    private final Map<String, ExchangeCodeCacheItem> exchangeCodeCache = new ConcurrentHashMap<>();

    @Override
    public String buildAuthorizeRedirectUrl(HttpServletRequest request, String redirectUri) {
        validateEnabled();
        validateBaseConfig();
        String finalRedirectUri = resolveRedirectUri(redirectUri, false);
        String callbackUrl = buildCallbackUrl(request, finalRedirectUri);
        return normalizeBaseUrl(kodSsoProperties.getBaseUrl())
                + "?user/sso/apiLogin&appName=" + HttpUtils.encodeUtf8(kodSsoProperties.getAppName())
                + "&callbackUrl=" + HttpUtils.encodeUtf8(callbackUrl);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public AuthLoginRespVO loginByKodToken(String kodAccessToken) {
        KodSsoResolvedUser resolvedUser = resolveOrCreateUser(kodAccessToken);
        return adminAuthService.createLoginToken(resolvedUser.getUserId(), resolvedUser.getUsername(),
                LoginLogTypeEnum.LOGIN_KOD_SSO);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public String buildClientRedirectUrl(String kodAccessToken, String redirectUri) {
        String finalRedirectUri = resolveRedirectUri(redirectUri, true);
        KodSsoResolvedUser resolvedUser = resolveOrCreateUser(kodAccessToken);
        String exchangeCode = IdUtil.fastSimpleUUID();
        exchangeCodeCache.put(exchangeCode, new ExchangeCodeCacheItem(
                resolvedUser.getUserId(), resolvedUser.getUsername(),
                LocalDateTime.now().plus(kodSsoProperties.getExchangeCodeExpire())));
        return HttpUtils.append(finalRedirectUri, Collections.singletonMap(EXCHANGE_CODE_PARAM, exchangeCode), null, false);
    }

    @Override
    public AuthLoginRespVO exchangeCode(String code) {
        ExchangeCodeCacheItem cacheItem = exchangeCodeCache.remove(code);
        if (cacheItem == null || cacheItem.getExpireTime().isBefore(LocalDateTime.now())) {
            throw exception(AUTH_KOD_SSO_EXCHANGE_CODE_NOT_FOUND);
        }
        return adminAuthService.createLoginToken(cacheItem.getUserId(), cacheItem.getUsername(),
                LoginLogTypeEnum.LOGIN_KOD_SSO);
    }

    private KodSsoResolvedUser resolveOrCreateUser(String kodAccessToken) {
        validateEnabled();
        validateBaseConfig();
        KodUserProfile profile = fetchKodUserProfile(kodAccessToken);
        KodSsoUserBindDO bind = kodSsoUserBindMapper.selectByKodUserId(profile.getKodUserId());
        if (bind != null) {
            syncBind(bind, profile);
            AdminUserDO user = adminUserService.getUser(bind.getUserId());
            if (user == null) {
                throw exception(USER_NOT_EXISTS);
            }
            syncLocalRoles(user.getId(), profile);
            syncLocalDept(user, profile);
            return new KodSsoResolvedUser(user.getId(), user.getUsername());
        }
        if (!Boolean.TRUE.equals(kodSsoProperties.getAutoCreateUser())) {
            throw exception(AUTH_KOD_SSO_AUTO_CREATE_DISABLED);
        }
        Long userId = createLocalUser(profile);
        createBind(userId, profile);
        AdminUserDO user = adminUserService.getUser(userId);
        return new KodSsoResolvedUser(userId, user.getUsername());
    }

    private KodUserProfile fetchKodUserProfile(String kodAccessToken) {
        if (StrUtil.isBlank(kodAccessToken)) {
            throw exception(AUTH_KOD_SSO_TOKEN_INVALID, "缺少可道云访问令牌");
        }
        String url = normalizeBaseUrl(kodSsoProperties.getBaseUrl())
                + "?user/sso/apiCheckToken&accessToken=" + HttpUtils.encodeUtf8(kodAccessToken)
                + "&appName=" + HttpUtils.encodeUtf8(kodSsoProperties.getAppName());
        String response = HttpUtils.get(url, Collections.emptyMap());
        if (!JsonUtils.isJsonObject(response)) {
            log.warn("可道云校验返回非 JSON，body={}", response);
            throw exception(AUTH_KOD_SSO_TOKEN_INVALID, "可道云校验返回异常");
        }
        JsonNode root = JsonUtils.parseTree(response);
        if (isFailureResponse(root)) {
            throw exception(AUTH_KOD_SSO_TOKEN_INVALID, extractErrorMessage(root));
        }
        JsonNode payload = root.has("data") && root.get("data").isObject() ? root.get("data") : root;
        String kodUserId = firstNonBlank(payload, "userID", "userId", "id");
        String kodUsername = firstNonBlank(payload, "name", "username", "userName");
        String kodNickname = firstNonBlank(payload, "nickName", "nickname", "displayName", "name");
        String email = firstNonBlank(payload, "email");
        String mobile = firstNonBlank(payload, "mobile", "phone", "tel");
        Long kodRoleId = firstLong(payload, "roleID", "roleId");
        Long deptId = extractLeafDeptId(payload);
        boolean isRoot = firstBoolean(payload, "isRoot", "root");
        if (StrUtil.isAllBlank(kodUserId, kodUsername)) {
            throw exception(AUTH_KOD_SSO_TOKEN_INVALID, "可道云返回缺少用户唯一标识");
        }
        if (StrUtil.isBlank(kodUserId)) {
            kodUserId = kodUsername;
        }
        return new KodUserProfile(kodUserId, kodUsername, StrUtil.blankToDefault(kodNickname, kodUsername),
                email, mobile, kodRoleId, deptId, isRoot, response);
    }

    private boolean isFailureResponse(JsonNode root) {
        if (root == null || root.isMissingNode()) {
            return true;
        }
        if (root.has("code")) {
            JsonNode code = root.get("code");
            if (code.isBoolean()) {
                return !code.booleanValue();
            }
            String codeText = code.asText();
            return "10001".equals(codeText) || "false".equalsIgnoreCase(codeText);
        }
        return false;
    }

    private String extractErrorMessage(JsonNode root) {
        String message = firstNonBlank(root, "data", "info", "message", "msg");
        return StrUtil.blankToDefault(message, "可道云校验失败");
    }

    private Long createLocalUser(KodUserProfile profile) {
        UserSaveReqVO createReqVO = new UserSaveReqVO();
        createReqVO.setUsername(generateUsername(profile));
        createReqVO.setNickname(StrUtil.blankToDefault(StrUtil.maxLength(profile.getKodNickname(), 30), createReqVO.getUsername()));
        createReqVO.setEmail(sanitizeEmail(profile.getEmail()));
        createReqVO.setMobile(sanitizeMobile(profile.getMobile()));
        createReqVO.setDeptId(resolveAvailableDeptId(profile));
        createReqVO.setPassword(UUID.fastUUID().toString(true).substring(0, 16));
        Long userId = runWithSystemOperatorContext(() -> adminUserService.createUser(createReqVO));
        syncLocalRoles(userId, profile);
        return userId;
    }

    private <T> T runWithSystemOperatorContext(Supplier<T> supplier) {
        if (SecurityFrameworkUtils.getLoginUser() != null) {
            return supplier.get();
        }
        HttpServletRequest request = ServletUtils.getRequest();
        Authentication oldAuthentication = SecurityFrameworkUtils.getAuthentication();
        Long oldRequestUserId = WebFrameworkUtils.getLoginUserId(request);
        Integer oldRequestUserType = WebFrameworkUtils.getLoginUserType(request);
        try {
            LoginUser systemOperator = new LoginUser();
            systemOperator.setId(1L);
            systemOperator.setUserType(UserTypeEnum.ADMIN.getValue());
            systemOperator.setTenantId(kodSsoProperties.getTenantId());
            if (request != null) {
                SecurityFrameworkUtils.setLoginUser(systemOperator, request);
            } else {
                SecurityContextHolder.getContext().setAuthentication(
                        new UsernamePasswordAuthenticationToken(systemOperator, null, Collections.emptyList()));
            }
            return supplier.get();
        } finally {
            if (oldAuthentication != null) {
                SecurityContextHolder.getContext().setAuthentication(oldAuthentication);
            } else {
                SecurityContextHolder.clearContext();
            }
            if (request != null) {
                WebFrameworkUtils.setLoginUserId(request, oldRequestUserId);
                WebFrameworkUtils.setLoginUserType(request, oldRequestUserType);
            }
        }
    }

    private void createBind(Long userId, KodUserProfile profile) {
        KodSsoUserBindDO bind = new KodSsoUserBindDO();
        bind.setUserId(userId);
        bind.setKodUserId(profile.getKodUserId());
        bind.setKodUsername(profile.getKodUsername());
        bind.setKodNickname(profile.getKodNickname());
        bind.setRawProfileJson(profile.getRawProfileJson());
        kodSsoUserBindMapper.insert(bind);
    }

    private void syncBind(KodSsoUserBindDO bind, KodUserProfile profile) {
        boolean changed = false;
        if (!StrUtil.equals(bind.getKodUsername(), profile.getKodUsername())) {
            bind.setKodUsername(profile.getKodUsername());
            changed = true;
        }
        if (!StrUtil.equals(bind.getKodNickname(), profile.getKodNickname())) {
            bind.setKodNickname(profile.getKodNickname());
            changed = true;
        }
        if (!StrUtil.equals(bind.getRawProfileJson(), profile.getRawProfileJson())) {
            bind.setRawProfileJson(profile.getRawProfileJson());
            changed = true;
        }
        if (changed) {
            kodSsoUserBindMapper.updateById(bind);
        }
    }

    private void syncLocalDept(AdminUserDO user, KodUserProfile profile) {
        Long targetDeptId = resolveAvailableDeptId(profile);
        if (Objects.equals(user.getDeptId(), targetDeptId)) {
            return;
        }
        adminUserService.updateUserDept(user.getId(), targetDeptId);
    }

    private Long resolveAvailableDeptId(KodUserProfile profile) {
        if (profile.getDeptId() == null) {
            return null;
        }
        DeptDO dept = deptService.getDept(profile.getDeptId());
        if (dept == null) {
            log.warn("可道云用户 {} 对应部门 {} 不存在，本次跳过部门同步", profile.getKodUserId(), profile.getDeptId());
            return null;
        }
        if (!Objects.equals(dept.getStatus(), CommonStatusEnum.ENABLE.getStatus())) {
            log.warn("可道云用户 {} 对应部门 {} 已禁用，本次跳过部门同步", profile.getKodUserId(), profile.getDeptId());
            return null;
        }
        return dept.getId();
    }

    private String generateUsername(KodUserProfile profile) {
        String prefix = sanitizeUsername(StrUtil.blankToDefault(kodSsoProperties.getUsernamePrefix(), "kod"));
        String raw = sanitizeUsername(StrUtil.blankToDefault(profile.getKodUsername(), profile.getKodUserId()));
        if (StrUtil.isBlank(raw)) {
            raw = Integer.toString(Math.abs(profile.getKodUserId().hashCode()));
        }
        String candidate = StrUtil.maxLength(prefix + raw, 30);
        if (candidate.length() < 4) {
            candidate = StrUtil.maxLength(prefix + "user" + raw, 30);
        }
        String base = candidate;
        int sequence = 1;
        while (adminUserService.getUserByUsername(candidate) != null) {
            String suffix = Integer.toString(sequence++);
            candidate = StrUtil.maxLength(base, 30 - suffix.length()) + suffix;
        }
        return candidate;
    }

    private String sanitizeUsername(String input) {
        String sanitized = StrUtil.blankToDefault(input, "").replaceAll("[^A-Za-z0-9]", "");
        if (StrUtil.isBlank(sanitized)) {
            return "kod";
        }
        return sanitized.toLowerCase();
    }

    private String sanitizeEmail(String email) {
        if (StrUtil.isBlank(email) || !StrUtil.contains(email, "@")) {
            return null;
        }
        return StrUtil.maxLength(email, 50);
    }

    private String sanitizeMobile(String mobile) {
        if (StrUtil.isBlank(mobile)) {
            return null;
        }
        String digits = mobile.replaceAll("[^0-9]", "");
        if (digits.length() != 11) {
            return null;
        }
        return digits;
    }

    private String resolveRedirectUri(String redirectUri, boolean required) {
        String finalRedirectUri = StrUtil.blankToDefault(redirectUri, kodSsoProperties.getRedirectUri());
        if (StrUtil.isBlank(finalRedirectUri)) {
            if (required) {
                throw exception(AUTH_KOD_SSO_REDIRECT_URI_INVALID);
            }
            return null;
        }
        if (!StrUtil.startWithAnyIgnoreCase(finalRedirectUri, "http://", "https://")) {
            throw exception(AUTH_KOD_SSO_REDIRECT_URI_INVALID);
        }
        return finalRedirectUri;
    }

    private String buildCallbackUrl(HttpServletRequest request, String redirectUri) {
        String callbackUrl = request.getRequestURL().toString().replace("/start", "/callback");
        if (StrUtil.isBlank(redirectUri)) {
            return callbackUrl;
        }
        return HttpUtils.append(callbackUrl, Collections.singletonMap("redirectUri", redirectUri), null, false);
    }

    private void validateEnabled() {
        if (!Boolean.TRUE.equals(kodSsoProperties.getEnabled())) {
            throw exception(AUTH_KOD_SSO_DISABLED);
        }
    }

    private void validateBaseConfig() {
        if (StrUtil.hasBlank(kodSsoProperties.getBaseUrl(), kodSsoProperties.getAppName())) {
            throw exception(AUTH_KOD_SSO_BAD_REQUEST, "缺少 baseUrl 或 appName 配置");
        }
    }

    private String normalizeBaseUrl(String baseUrl) {
        return StrUtil.removeSuffix(baseUrl, "/") + "/";
    }

    private void syncLocalRoles(Long userId, KodUserProfile profile) {
        Set<Long> currentRoleIds = permissionService.getUserRoleIdListByUserId(userId);
        Set<Long> targetRoleIds = new HashSet<>(CollUtil.emptyIfNull(currentRoleIds));
        targetRoleIds.removeAll(getManagedLocalRoleIds());

        Long mappedRoleId = resolveLocalRoleId(profile);
        if (mappedRoleId != null) {
            targetRoleIds.add(mappedRoleId);
        } else if (CollUtil.isNotEmpty(kodSsoProperties.getDefaultRoleIds())) {
            targetRoleIds.addAll(kodSsoProperties.getDefaultRoleIds());
            log.warn("可道云用户 {} 未匹配到角色映射，回退使用默认角色 {}", profile.getKodUserId(),
                    kodSsoProperties.getDefaultRoleIds());
        } else {
            log.warn("可道云用户 {} 未匹配到角色映射，且未配置默认角色，登录后可能看不到任何菜单", profile.getKodUserId());
        }

        if (!Objects.equals(targetRoleIds, currentRoleIds)) {
            permissionService.assignUserRole(userId, targetRoleIds);
        }
    }

    private Set<Long> getManagedLocalRoleIds() {
        Set<Long> roleIds = new HashSet<>();
        addRoleId(roleIds, kodSsoProperties.getLocalSuperAdminRoleId());
        addRoleId(roleIds, kodSsoProperties.getLocalDeptAdminRoleId());
        addRoleId(roleIds, kodSsoProperties.getLocalCommonRoleId());
        return roleIds;
    }

    private Long resolveLocalRoleId(KodUserProfile profile) {
        if (profile.isRoot() || ObjectUtil.equal(profile.getKodRoleId(), kodSsoProperties.getKodSuperAdminRoleId())) {
            return kodSsoProperties.getLocalSuperAdminRoleId();
        }
        if (ObjectUtil.equal(profile.getKodRoleId(), kodSsoProperties.getKodDeptAdminRoleId())) {
            return kodSsoProperties.getLocalDeptAdminRoleId();
        }
        if (ObjectUtil.equal(profile.getKodRoleId(), kodSsoProperties.getKodCommonRoleId())) {
            return kodSsoProperties.getLocalCommonRoleId();
        }
        return null;
    }

    private void addRoleId(Set<Long> roleIds, Long roleId) {
        if (roleId != null && roleId > 0) {
            roleIds.add(roleId);
        }
    }

    private String firstNonBlank(JsonNode node, String... fields) {
        for (String field : fields) {
            JsonNode value = node.get(field);
            if (value != null && !value.isNull() && StrUtil.isNotBlank(value.asText())) {
                return value.asText();
            }
        }
        return null;
    }

    private Long firstLong(JsonNode node, String... fields) {
        String value = firstNonBlank(node, fields);
        if (StrUtil.isBlank(value) || !StrUtil.isNumeric(value)) {
            return null;
        }
        return Long.valueOf(value);
    }

    private Long extractLeafDeptId(JsonNode node) {
        JsonNode groupInfo = node.get("groupInfo");
        if (groupInfo == null || !groupInfo.isArray() || groupInfo.isEmpty()) {
            return null;
        }
        JsonNode leafGroup = groupInfo.get(groupInfo.size() - 1);
        return firstLong(leafGroup, "groupID", "groupId", "id");
    }

    private boolean firstBoolean(JsonNode node, String... fields) {
        for (String field : fields) {
            JsonNode value = node.get(field);
            if (value == null || value.isNull()) {
                continue;
            }
            if (value.isBoolean()) {
                return value.booleanValue();
            }
            String text = value.asText();
            if (StrUtil.isBlank(text)) {
                continue;
            }
            if ("1".equals(text) || "true".equalsIgnoreCase(text)) {
                return true;
            }
            if ("0".equals(text) || "false".equalsIgnoreCase(text)) {
                return false;
            }
        }
        return false;
    }

    @Data
    @AllArgsConstructor
    private static class KodUserProfile {
        private String kodUserId;
        private String kodUsername;
        private String kodNickname;
        private String email;
        private String mobile;
        private Long kodRoleId;
        private Long deptId;
        private boolean root;
        private String rawProfileJson;
    }

    @Data
    @AllArgsConstructor
    private static class KodSsoResolvedUser {
        private Long userId;
        private String username;
    }

    @Data
    @AllArgsConstructor
    private static class ExchangeCodeCacheItem {
        private Long userId;
        private String username;
        private LocalDateTime expireTime;
    }

}
