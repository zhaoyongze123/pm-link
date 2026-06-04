package cn.iocoder.yudao.module.bpm.framework.notify;

import cn.iocoder.yudao.framework.common.enums.CommonStatusEnum;
import cn.iocoder.yudao.module.bpm.enums.message.BpmMessageEnum;
import cn.iocoder.yudao.module.system.controller.admin.notify.vo.template.NotifyTemplateSaveReqVO;
import cn.iocoder.yudao.module.system.enums.notify.NotifyTemplateTypeEnum;
import cn.iocoder.yudao.module.system.service.notify.NotifyTemplateService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;

/**
 * BPM 站内信模板初始化。
 *
 * <p>审批待办通知需要持久化到 system_notify_message，这里在启动时幂等补齐模板，
 * 避免本地环境或新环境忘记手工创建模板导致消息发送失败。</p>
 */
@Component
@Slf4j
public class BpmNotifyTemplateInitRunner implements ApplicationRunner {

    private static final String TASK_ASSIGNED_NOTIFY_TEMPLATE_CODE = BpmMessageEnum.TASK_ASSIGNED.getSmsTemplateCode();

    @Resource
    private NotifyTemplateService notifyTemplateService;

    @Override
    public void run(ApplicationArguments args) {
        if (notifyTemplateService.getNotifyTemplateByCodeFromCache(TASK_ASSIGNED_NOTIFY_TEMPLATE_CODE) != null) {
            return;
        }
        NotifyTemplateSaveReqVO createReqVO = new NotifyTemplateSaveReqVO();
        createReqVO.setName("【工作流】任务被分配");
        createReqVO.setCode(TASK_ASSIGNED_NOTIFY_TEMPLATE_CODE);
        createReqVO.setType(NotifyTemplateTypeEnum.SYSTEM_MESSAGE.getType());
        createReqVO.setNickname("审批中心");
        createReqVO.setContent("您收到了一条新的待办任务：{processInstanceName}-{taskName}，申请人：{startUserNickname}");
        createReqVO.setStatus(CommonStatusEnum.ENABLE.getStatus());
        createReqVO.setRemark("BPM 待办分配通知模板，供 oa-lite 与管理后台共用");
        Long templateId = notifyTemplateService.createNotifyTemplate(createReqVO);
        log.info("[run][已自动初始化 BPM 待办站内信模板，templateId={} code={}]", templateId, TASK_ASSIGNED_NOTIFY_TEMPLATE_CODE);
    }
}
