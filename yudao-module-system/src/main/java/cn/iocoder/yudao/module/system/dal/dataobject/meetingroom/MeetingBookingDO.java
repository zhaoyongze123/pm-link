package cn.iocoder.yudao.module.system.dal.dataobject.meetingroom;

import cn.iocoder.yudao.framework.tenant.core.db.TenantBaseDO;
import com.baomidou.mybatisplus.annotation.KeySequence;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.time.LocalDateTime;

/**
 * 会议室预定 DO
 */
@TableName("system_meeting_booking")
@KeySequence("system_meeting_booking_seq")
@Data
@EqualsAndHashCode(callSuper = true)
public class MeetingBookingDO extends TenantBaseDO {

    @TableId
    private Long id;

    /**
     * 会议主题
     */
    private String subject;

    /**
     * 会议室编号
     */
    private Long meetingRoomId;

    /**
     * 开始时间
     */
    private LocalDateTime startTime;

    /**
     * 结束时间
     */
    private LocalDateTime endTime;

    /**
     * 申请人编号
     */
    private Long applicantUserId;

    /**
     * 备注
     */
    private String remark;

    /**
     * 状态
     */
    private Integer status;

    /**
     * 是否忽略冲突提醒保存
     */
    private Boolean forceConflict;

    /**
     * 取消原因
     */
    private String cancelReason;

    /**
     * 取消类型
     */
    private Integer cancelType;

}
