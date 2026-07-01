package cn.iocoder.yudao.module.system.controller.admin.partyfile.vo.kodsource;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.Data;

import java.util.List;

@Schema(description = "管理后台 - 党务文件可道云目录树节点 Response VO")
@Data
public class PartyFileKodFolderRespVO {

    private String key;

    private String title;

    private String value;

    private String path;

    private List<PartyFileKodFolderRespVO> children;
}
