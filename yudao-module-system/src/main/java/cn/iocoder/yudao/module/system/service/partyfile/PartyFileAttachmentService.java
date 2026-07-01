package cn.iocoder.yudao.module.system.service.partyfile;

import cn.iocoder.yudao.module.infra.dal.dataobject.file.FileDO;
import cn.iocoder.yudao.module.system.controller.admin.partyfile.vo.file.PartyFileKodFileRespVO;
import cn.iocoder.yudao.module.system.controller.admin.partyfile.vo.file.PartyFileKodSelectReqVO;
import cn.iocoder.yudao.module.system.controller.admin.partyfile.vo.file.PartyFileAttachmentUploadRespVO;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;

public interface PartyFileAttachmentService {

    PartyFileAttachmentUploadRespVO uploadAttachment(MultipartFile file, Integer storageType, Long kodSourceId,
                                                     String kodFolderPath) throws Exception;

    List<PartyFileKodFileRespVO> getKodFiles(Long kodSourceId, String kodFolderPath);

    List<PartyFileAttachmentUploadRespVO> selectKodFiles(PartyFileKodSelectReqVO reqVO);

    FileDO getFile(Long fileId);

    byte[] getAttachmentContent(Long fileId) throws Exception;
}
