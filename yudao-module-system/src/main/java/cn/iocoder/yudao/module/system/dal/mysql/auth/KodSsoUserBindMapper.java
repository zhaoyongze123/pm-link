package cn.iocoder.yudao.module.system.dal.mysql.auth;

import cn.iocoder.yudao.framework.mybatis.core.mapper.BaseMapperX;
import cn.iocoder.yudao.framework.mybatis.core.query.LambdaQueryWrapperX;
import cn.iocoder.yudao.module.system.dal.dataobject.auth.KodSsoUserBindDO;
import org.apache.ibatis.annotations.Mapper;

@Mapper
public interface KodSsoUserBindMapper extends BaseMapperX<KodSsoUserBindDO> {

    default KodSsoUserBindDO selectByKodUserId(String kodUserId) {
        return selectOne(KodSsoUserBindDO::getKodUserId, kodUserId);
    }

    default KodSsoUserBindDO selectByKodUsername(String kodUsername) {
        return selectOne(KodSsoUserBindDO::getKodUsername, kodUsername);
    }

    default void deleteByKodUserId(String kodUserId) {
        delete(new LambdaQueryWrapperX<KodSsoUserBindDO>()
                .eq(KodSsoUserBindDO::getKodUserId, kodUserId));
    }

    default KodSsoUserBindDO selectByUserId(Long userId) {
        return selectOne(KodSsoUserBindDO::getUserId, userId);
    }

    default void deleteByUserId(Long userId) {
        delete(new LambdaQueryWrapperX<KodSsoUserBindDO>()
                .eq(KodSsoUserBindDO::getUserId, userId));
    }

}
