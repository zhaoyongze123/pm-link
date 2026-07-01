package cn.iocoder.yudao.module.system.dal.dataobject.partyfile;

import cn.iocoder.yudao.framework.mybatis.core.dataobject.BaseDO;
import cn.iocoder.yudao.framework.mybatis.core.type.EncryptTypeHandler;
import cn.iocoder.yudao.framework.tenant.core.aop.TenantIgnore;
import com.baomidou.mybatisplus.annotation.KeySequence;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.time.LocalDateTime;

@TableName(value = "party_file_kod_source", autoResultMap = true)
@KeySequence("party_file_kod_source_seq")
@Data
@EqualsAndHashCode(callSuper = true)
@TenantIgnore
public class PartyFileKodSourceDO extends BaseDO {

    @TableId
    private Long id;

    private String name;

    private String baseUrl;

    private String appName;

    private String accessToken;

    private String serviceUsername;

    @TableField(typeHandler = EncryptTypeHandler.class)
    private String servicePassword;

    private LocalDateTime tokenExpireTime;

    private String rootFolderPath;

    private String rootFolderName;

    private Integer status;

    private Boolean isDefault;
}
