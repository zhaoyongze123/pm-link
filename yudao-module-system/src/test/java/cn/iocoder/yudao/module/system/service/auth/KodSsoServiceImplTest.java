package cn.iocoder.yudao.module.system.service.auth;

import cn.iocoder.yudao.framework.common.util.http.HttpUtils;
import cn.iocoder.yudao.framework.test.core.ut.BaseDbUnitTest;
import cn.iocoder.yudao.module.system.controller.admin.auth.vo.AuthLoginRespVO;
import cn.iocoder.yudao.module.system.controller.admin.user.vo.user.UserSaveReqVO;
import cn.iocoder.yudao.module.system.dal.dataobject.auth.KodSsoUserBindDO;
import cn.iocoder.yudao.module.system.dal.dataobject.dept.DeptDO;
import cn.iocoder.yudao.module.system.dal.dataobject.user.AdminUserDO;
import cn.iocoder.yudao.module.system.dal.mysql.auth.KodSsoUserBindMapper;
import cn.iocoder.yudao.module.system.framework.kodsso.config.KodSsoConfiguration;
import cn.iocoder.yudao.module.system.framework.kodsso.config.KodSsoProperties;
import cn.iocoder.yudao.module.system.service.dept.DeptService;
import cn.iocoder.yudao.module.system.service.permission.PermissionService;
import cn.iocoder.yudao.module.system.service.user.AdminUserService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;

import javax.annotation.Resource;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;

import static cn.iocoder.yudao.framework.test.core.util.AssertUtils.assertPojoEquals;
import static cn.iocoder.yudao.framework.test.core.util.RandomUtils.randomPojo;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

@Import({KodSsoServiceImpl.class, KodSsoConfiguration.class})
public class KodSsoServiceImplTest extends BaseDbUnitTest {

    @Resource
    private KodSsoServiceImpl kodSsoService;
    @Resource
    private KodSsoProperties kodSsoProperties;

    @MockBean
    private KodSsoUserBindMapper kodSsoUserBindMapper;
    @MockBean
    private AdminUserService adminUserService;
    @MockBean
    private AdminAuthService adminAuthService;
    @MockBean
    private PermissionService permissionService;
    @MockBean
    private DeptService deptService;

    @BeforeEach
    public void setUp() {
        kodSsoProperties.setEnabled(true);
        kodSsoProperties.setBaseUrl("https://kod.example.com/");
        kodSsoProperties.setAppName("oa-lite");
        kodSsoProperties.setAutoCreateUser(true);
        kodSsoProperties.setUsernamePrefix("kod");
        kodSsoProperties.setDefaultRoleIds(Collections.emptySet());
        kodSsoProperties.setRedirectUri(null);
        kodSsoProperties.setKodCommonRoleId(1L);
        kodSsoProperties.setKodDeptAdminRoleId(2L);
        kodSsoProperties.setKodSuperAdminRoleId(3L);
        kodSsoProperties.setLocalCommonRoleId(2L);
        kodSsoProperties.setLocalDeptAdminRoleId(3L);
        kodSsoProperties.setLocalSuperAdminRoleId(1L);
        when(deptService.getDept(eq(2L))).thenReturn(new DeptDO().setId(2L).setStatus(0));
        when(deptService.getDept(eq(3L))).thenReturn(new DeptDO().setId(3L).setStatus(0));
    }

    @Test
    public void testBuildClientRedirectUrl_andExchange_success() {
        KodSsoUserBindDO bind = new KodSsoUserBindDO();
        bind.setUserId(11L);
        bind.setKodUserId("u-1");
        when(kodSsoUserBindMapper.selectByKodUserId(eq("u-1"))).thenReturn(bind);
        when(adminUserService.getUser(eq(11L))).thenReturn(new AdminUserDO().setId(11L).setUsername("koduser"));

        AuthLoginRespVO loginRespVO = randomPojo(AuthLoginRespVO.class, o -> o.setUserId(11L));
        when(adminAuthService.createLoginToken(eq(11L), eq("koduser"), any())).thenReturn(loginRespVO);

        try (MockedStatic<HttpUtils> mockedHttpUtils = mockStatic(HttpUtils.class, CALLS_REAL_METHODS)) {
            mockedHttpUtils.when(() -> HttpUtils.get(eq("https://kod.example.com/?user/sso/apiCheckToken&accessToken=kod-token&appName=oa-lite"),
                    eq(Collections.emptyMap())))
                    .thenReturn("{\"id\":\"u-1\",\"name\":\"koduser\",\"nickName\":\"可道云用户\"}");

            String redirectUrl = kodSsoService.buildClientRedirectUrl("kod-token", "http://127.0.0.1:3000/callback");
            assertTrue(redirectUrl.contains("kodSsoCode="));
            String exchangeCode = redirectUrl.substring(redirectUrl.indexOf("kodSsoCode=") + "kodSsoCode=".length());

            AuthLoginRespVO result = kodSsoService.exchangeCode(exchangeCode);
            assertPojoEquals(loginRespVO, result);
        }
    }

    @Test
    public void testLoginByKodToken_autoCreateUser_assignMappedRole() {
        when(kodSsoUserBindMapper.selectByKodUserId(eq("u-2"))).thenReturn(null);
        when(adminUserService.getUserByUsername(any())).thenReturn(null);
        when(adminUserService.createUser(any(UserSaveReqVO.class))).thenReturn(22L);
        when(adminUserService.getUser(eq(22L))).thenReturn(new AdminUserDO().setId(22L).setUsername("kodalice"));
        when(permissionService.getUserRoleIdListByUserId(eq(22L))).thenReturn(Collections.emptySet());

        AuthLoginRespVO loginRespVO = randomPojo(AuthLoginRespVO.class, o -> o.setUserId(22L));
        when(adminAuthService.createLoginToken(eq(22L), eq("kodalice"), any())).thenReturn(loginRespVO);

        try (MockedStatic<HttpUtils> mockedHttpUtils = mockStatic(HttpUtils.class, CALLS_REAL_METHODS)) {
            mockedHttpUtils.when(() -> HttpUtils.get(eq("https://kod.example.com/?user/sso/apiCheckToken&accessToken=kod-token-2&appName=oa-lite"),
                    eq(Collections.emptyMap())))
                    .thenReturn("{\"id\":\"u-2\",\"name\":\"alice\",\"nickName\":\"Alice\",\"email\":\"alice@example.com\",\"roleID\":1,"
                            + "\"groupInfo\":[{\"groupID\":\"2\",\"groupName\":\"销售部\"}]}");

            AuthLoginRespVO result = kodSsoService.loginByKodToken("kod-token-2");
            assertPojoEquals(loginRespVO, result);
        }

        verify(adminUserService).createUser(argThat(reqVO ->
                reqVO.getUsername().startsWith("kod")
                        && "Alice".equals(reqVO.getNickname())
                        && Long.valueOf(2L).equals(reqVO.getDeptId())));
        verify(permissionService).assignUserRole(eq(22L), eq(Collections.singleton(2L)));
        verify(kodSsoUserBindMapper).insert(argThat((KodSsoUserBindDO bind) ->
                bind.getUserId().equals(22L)
                        && "u-2".equals(bind.getKodUserId())
                        && "alice".equals(bind.getKodUsername())));
    }

    @Test
    public void testLoginByKodToken_boundUser_syncMappedRoleAndKeepOtherRoles() {
        KodSsoUserBindDO bind = new KodSsoUserBindDO();
        bind.setUserId(33L);
        bind.setKodUserId("u-3");
        when(kodSsoUserBindMapper.selectByKodUserId(eq("u-3"))).thenReturn(bind);
        when(adminUserService.getUser(eq(33L))).thenReturn(new AdminUserDO().setId(33L).setUsername("kodbob").setDeptId(2L));
        when(permissionService.getUserRoleIdListByUserId(eq(33L)))
                .thenReturn(new HashSet<>(Arrays.asList(2L, 9L)));

        AuthLoginRespVO loginRespVO = randomPojo(AuthLoginRespVO.class, o -> o.setUserId(33L));
        when(adminAuthService.createLoginToken(eq(33L), eq("kodbob"), any())).thenReturn(loginRespVO);

        try (MockedStatic<HttpUtils> mockedHttpUtils = mockStatic(HttpUtils.class, CALLS_REAL_METHODS)) {
            mockedHttpUtils.when(() -> HttpUtils.get(eq("https://kod.example.com/?user/sso/apiCheckToken&accessToken=kod-token-3&appName=oa-lite"),
                    eq(Collections.emptyMap())))
                    .thenReturn("{\"id\":\"u-3\",\"name\":\"bob\",\"nickName\":\"Bob\",\"roleID\":2,\"isRoot\":0,"
                            + "\"groupInfo\":[{\"groupID\":\"1\",\"groupName\":\"总公司\"},{\"groupID\":\"3\",\"groupName\":\"项目部\"}]}");

            AuthLoginRespVO result = kodSsoService.loginByKodToken("kod-token-3");
            assertPojoEquals(loginRespVO, result);
        }

        verify(permissionService).assignUserRole(eq(33L), eq(new HashSet<>(Arrays.asList(3L, 9L))));
        verify(adminUserService).updateUserDept(eq(33L), eq(3L));
        verify(kodSsoUserBindMapper).updateById(argThat((KodSsoUserBindDO updatedBind) ->
                updatedBind.getUserId().equals(33L)
                        && "bob".equals(updatedBind.getKodUsername())));
    }

    @Test
    public void testLoginByKodToken_rootUser_syncSuperAdminRole() {
        KodSsoUserBindDO bind = new KodSsoUserBindDO();
        bind.setUserId(44L);
        bind.setKodUserId("u-4");
        when(kodSsoUserBindMapper.selectByKodUserId(eq("u-4"))).thenReturn(bind);
        when(adminUserService.getUser(eq(44L))).thenReturn(new AdminUserDO().setId(44L).setUsername("kodroot"));
        when(permissionService.getUserRoleIdListByUserId(eq(44L))).thenReturn(Collections.singleton(3L));

        AuthLoginRespVO loginRespVO = randomPojo(AuthLoginRespVO.class, o -> o.setUserId(44L));
        when(adminAuthService.createLoginToken(eq(44L), eq("kodroot"), any())).thenReturn(loginRespVO);

        try (MockedStatic<HttpUtils> mockedHttpUtils = mockStatic(HttpUtils.class, CALLS_REAL_METHODS)) {
            mockedHttpUtils.when(() -> HttpUtils.get(eq("https://kod.example.com/?user/sso/apiCheckToken&accessToken=kod-token-4&appName=oa-lite"),
                    eq(Collections.emptyMap())))
                    .thenReturn("{\"id\":\"u-4\",\"name\":\"root\",\"nickName\":\"Root\",\"roleID\":3,\"isRoot\":1}");

            AuthLoginRespVO result = kodSsoService.loginByKodToken("kod-token-4");
            assertPojoEquals(loginRespVO, result);
        }

        verify(permissionService).assignUserRole(eq(44L), eq(Collections.singleton(1L)));
    }

}
