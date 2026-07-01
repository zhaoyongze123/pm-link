package cn.iocoder.yudao.module.system.controller.admin.partyfile;

import cn.iocoder.yudao.framework.common.pojo.CommonResult;
import cn.iocoder.yudao.framework.common.pojo.PageResult;
import cn.iocoder.yudao.framework.common.util.object.BeanUtils;
import cn.iocoder.yudao.module.system.controller.admin.partyfile.vo.kodsource.PartyFileKodFolderRespVO;
import cn.iocoder.yudao.module.system.controller.admin.partyfile.vo.kodsource.PartyFileKodSourcePageReqVO;
import cn.iocoder.yudao.module.system.controller.admin.partyfile.vo.kodsource.PartyFileKodSourceRespVO;
import cn.iocoder.yudao.module.system.controller.admin.partyfile.vo.kodsource.PartyFileKodSourceSaveReqVO;
import cn.iocoder.yudao.module.system.dal.dataobject.partyfile.PartyFileKodSourceDO;
import cn.iocoder.yudao.module.system.service.partyfile.PartyFileKodSourceService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

import javax.annotation.Resource;
import javax.validation.Valid;
import java.util.List;

import static cn.iocoder.yudao.framework.common.pojo.CommonResult.success;

@Tag(name = "管理后台 - 党务文件可道云目录来源")
@RestController
@RequestMapping("/system/party-file-kod-source")
@Validated
public class PartyFileKodSourceController {

    @Resource
    private PartyFileKodSourceService partyFileKodSourceService;

    @PostMapping("/create")
    @Operation(summary = "创建可道云目录来源")
    @PreAuthorize("@ss.hasPermission('system:party-file:update')")
    public CommonResult<Long> create(@Valid @RequestBody PartyFileKodSourceSaveReqVO reqVO) {
        return success(partyFileKodSourceService.create(reqVO));
    }

    @PutMapping("/update")
    @Operation(summary = "修改可道云目录来源")
    @PreAuthorize("@ss.hasPermission('system:party-file:update')")
    public CommonResult<Boolean> update(@Valid @RequestBody PartyFileKodSourceSaveReqVO reqVO) {
        partyFileKodSourceService.update(reqVO);
        return success(true);
    }

    @DeleteMapping("/delete")
    @Operation(summary = "删除可道云目录来源")
    @PreAuthorize("@ss.hasPermission('system:party-file:update')")
    public CommonResult<Boolean> delete(@RequestParam("id") Long id) {
        partyFileKodSourceService.delete(id);
        return success(true);
    }

    @GetMapping("/get")
    @Operation(summary = "获取可道云目录来源详情")
    @PreAuthorize("@ss.hasPermission('system:party-file:query')")
    public CommonResult<PartyFileKodSourceRespVO> get(@RequestParam("id") Long id) {
        return success(BeanUtils.toBean(partyFileKodSourceService.get(id), PartyFileKodSourceRespVO.class));
    }

    @GetMapping("/page")
    @Operation(summary = "分页获取可道云目录来源")
    @PreAuthorize("@ss.hasPermission('system:party-file:query')")
    public CommonResult<PageResult<PartyFileKodSourceRespVO>> page(@Valid PartyFileKodSourcePageReqVO reqVO) {
        PageResult<PartyFileKodSourceDO> pageResult = partyFileKodSourceService.getPage(reqVO);
        return success(BeanUtils.toBean(pageResult, PartyFileKodSourceRespVO.class));
    }

    @GetMapping("/simple-list")
    @Operation(summary = "获取启用的可道云目录来源")
    @PreAuthorize("@ss.hasPermission('system:party-file:query')")
    public CommonResult<List<PartyFileKodSourceRespVO>> simpleList() {
        return success(BeanUtils.toBean(partyFileKodSourceService.getSimpleList(), PartyFileKodSourceRespVO.class));
    }

    @GetMapping("/folder-tree")
    @Operation(summary = "获取可道云目录树")
    @Parameter(name = "id", description = "来源编号", required = true)
    @PreAuthorize("@ss.hasPermission('system:party-file:query')")
    public CommonResult<List<PartyFileKodFolderRespVO>> folderTree(@RequestParam("id") Long id) {
        return success(partyFileKodSourceService.getFolderTree(id));
    }
}
