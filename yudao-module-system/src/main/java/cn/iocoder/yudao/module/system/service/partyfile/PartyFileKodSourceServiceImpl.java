package cn.iocoder.yudao.module.system.service.partyfile;

import cn.hutool.core.collection.CollUtil;
import cn.hutool.core.util.StrUtil;
import cn.hutool.http.HttpRequest;
import cn.hutool.http.HttpResponse;
import cn.iocoder.yudao.framework.common.enums.CommonStatusEnum;
import cn.iocoder.yudao.framework.common.pojo.PageResult;
import cn.iocoder.yudao.framework.common.util.object.BeanUtils;
import cn.iocoder.yudao.framework.common.util.json.JsonUtils;
import cn.iocoder.yudao.framework.common.util.http.HttpUtils;
import cn.iocoder.yudao.module.system.controller.admin.partyfile.vo.kodsource.PartyFileKodFolderRespVO;
import cn.iocoder.yudao.module.system.controller.admin.partyfile.vo.kodsource.PartyFileKodSourcePageReqVO;
import cn.iocoder.yudao.module.system.controller.admin.partyfile.vo.kodsource.PartyFileKodSourceSaveReqVO;
import cn.iocoder.yudao.module.system.dal.dataobject.partyfile.PartyFileDO;
import cn.iocoder.yudao.module.system.dal.dataobject.partyfile.PartyFileKodSourceDO;
import cn.iocoder.yudao.module.system.dal.mysql.partyfile.PartyFileKodSourceMapper;
import cn.iocoder.yudao.module.system.dal.mysql.partyfile.PartyFileMapper;
import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.stereotype.Service;
import org.springframework.validation.annotation.Validated;

import javax.annotation.Resource;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;

import static cn.iocoder.yudao.framework.common.exception.util.ServiceExceptionUtil.exception;
import static cn.iocoder.yudao.module.system.enums.ErrorCodeConstants.*;

@Service
@Validated
public class PartyFileKodSourceServiceImpl implements PartyFileKodSourceService {

    @Resource
    private PartyFileKodSourceMapper partyFileKodSourceMapper;
    @Resource
    private PartyFileMapper partyFileMapper;

    @Override
    public Long create(PartyFileKodSourceSaveReqVO reqVO) {
        validateNameUnique(reqVO.getName(), null);
        PartyFileKodSourceDO source = BeanUtils.toBean(reqVO, PartyFileKodSourceDO.class);
        source.setBaseUrl(normalizeBaseUrl(reqVO.getBaseUrl()));
        source.setRootFolderPath(normalizeFolderPath(reqVO.getRootFolderPath()));
        source.setIsDefault(Boolean.TRUE.equals(reqVO.getIsDefault()));
        if (Boolean.TRUE.equals(source.getIsDefault())) {
            clearDefaultFlag();
        }
        partyFileKodSourceMapper.insert(source);
        return source.getId();
    }

    @Override
    public void update(PartyFileKodSourceSaveReqVO reqVO) {
        PartyFileKodSourceDO exists = validateExists(reqVO.getId());
        validateNameUnique(reqVO.getName(), reqVO.getId());
        PartyFileKodSourceDO updateObj = BeanUtils.toBean(reqVO, PartyFileKodSourceDO.class);
        updateObj.setBaseUrl(normalizeBaseUrl(reqVO.getBaseUrl()));
        updateObj.setRootFolderPath(normalizeFolderPath(reqVO.getRootFolderPath()));
        updateObj.setIsDefault(Boolean.TRUE.equals(reqVO.getIsDefault()));
        if (Boolean.TRUE.equals(updateObj.getIsDefault())) {
            clearDefaultFlag();
        } else if (Boolean.TRUE.equals(exists.getIsDefault())) {
            updateObj.setIsDefault(false);
        }
        partyFileKodSourceMapper.updateById(updateObj);
    }

    @Override
    public void delete(Long id) {
        validateExists(id);
        List<PartyFileDO> usingFiles = partyFileMapper.selectListByKodSourceId(id);
        if (CollUtil.isNotEmpty(usingFiles)) {
            throw exception(PARTY_FILE_KOD_SOURCE_IN_USE);
        }
        partyFileKodSourceMapper.deleteById(id);
    }

    @Override
    public PartyFileKodSourceDO get(Long id) {
        return validateExists(id);
    }

    @Override
    public List<PartyFileKodSourceDO> getSimpleList() {
        return partyFileKodSourceMapper.selectEnabledList();
    }

    @Override
    public PageResult<PartyFileKodSourceDO> getPage(PartyFileKodSourcePageReqVO reqVO) {
        return partyFileKodSourceMapper.selectPage(reqVO);
    }

    @Override
    public List<PartyFileKodFolderRespVO> getFolderTree(Long id) {
        PartyFileKodSourceDO source = validateExists(id);
        return Collections.singletonList(buildFolderNode(source.getRootFolderName(), source.getRootFolderPath(),
                loadChildren(source, source.getRootFolderPath())));
    }

    public PartyFileKodSourceDO getEnabledSource(Long id) {
        PartyFileKodSourceDO source = validateExists(id);
        if (!Objects.equals(source.getStatus(), CommonStatusEnum.ENABLE.getStatus())) {
            throw exception(PARTY_FILE_STORAGE_CONFIG_INVALID);
        }
        return source;
    }

    private List<PartyFileKodFolderRespVO> loadChildren(PartyFileKodSourceDO source, String path) {
        JsonNode current = requestKodFolderList(source, path);
        JsonNode folderList = current.path("folderList");
        if (!folderList.isArray() || folderList.isEmpty()) {
            return Collections.emptyList();
        }
        List<PartyFileKodFolderRespVO> result = new ArrayList<>();
        for (JsonNode folder : folderList) {
            String childPath = firstNonBlank(folder, "path", "sourceID");
            String childName = firstNonBlank(folder, "name", "pathDisplay");
            if (StrUtil.isBlank(childPath) || StrUtil.isBlank(childName)) {
                continue;
            }
            result.add(buildFolderNode(childName, childPath, loadChildren(source, childPath)));
        }
        return result;
    }

    private PartyFileKodFolderRespVO buildFolderNode(String name, String path, List<PartyFileKodFolderRespVO> children) {
        PartyFileKodFolderRespVO node = new PartyFileKodFolderRespVO();
        node.setKey(path);
        node.setTitle(name);
        node.setValue(path);
        node.setPath(path);
        node.setChildren(children);
        return node;
    }

    public JsonNode requestKodFolderList(PartyFileKodSourceDO source, String path) {
        String url = source.getBaseUrl()
                + "?explorer/list/path&accessToken=" + HttpUtils.encodeUtf8(source.getAccessToken())
                + "&path=" + HttpUtils.encodeUtf8(normalizeFolderPath(path));
        try (HttpResponse response = HttpRequest.get(url).execute()) {
            String body = response.body();
            JsonNode root = JsonUtils.parseTree(body);
            if (root == null || root.isMissingNode()) {
                throw exception(PARTY_FILE_KOD_REQUEST_FAILED, "目录返回为空");
            }
            JsonNode data = root.path("data");
            if (isKodFailure(root, data)) {
                throw exception(PARTY_FILE_KOD_REQUEST_FAILED, extractKodMessage(root, data));
            }
            return data.isObject() ? data : root;
        } catch (Exception ex) {
            if (ex instanceof cn.iocoder.yudao.framework.common.exception.ServiceException) {
                throw ex;
            }
            throw exception(PARTY_FILE_KOD_REQUEST_FAILED, ex.getMessage());
        }
    }

    private boolean isKodFailure(JsonNode root, JsonNode data) {
        if (root.has("code")) {
            JsonNode code = root.get("code");
            if (code.isBoolean()) {
                return !code.booleanValue();
            }
            return "false".equalsIgnoreCase(code.asText()) || "10001".equals(code.asText());
        }
        return data.has("code") && !"true".equalsIgnoreCase(data.get("code").asText());
    }

    private String extractKodMessage(JsonNode root, JsonNode data) {
        String message = firstNonBlank(root, "data", "msg", "message", "info");
        if (StrUtil.isBlank(message) && data != null && data.isObject()) {
            message = firstNonBlank(data, "msg", "message", "info");
        }
        return StrUtil.blankToDefault(message, "可道云接口返回失败");
    }

    private String firstNonBlank(JsonNode node, String... fieldNames) {
        if (node == null || node.isMissingNode()) {
            return null;
        }
        for (String fieldName : fieldNames) {
            JsonNode value = node.get(fieldName);
            if (value != null && !value.isNull()) {
                String text = value.asText();
                if (StrUtil.isNotBlank(text)) {
                    return text;
                }
            }
        }
        return null;
    }

    private void validateNameUnique(String name, Long id) {
        PartyFileKodSourceDO exists = partyFileKodSourceMapper.selectByName(name);
        if (exists != null && !Objects.equals(exists.getId(), id)) {
            throw exception(PARTY_FILE_KOD_SOURCE_NAME_DUPLICATE);
        }
    }

    private PartyFileKodSourceDO validateExists(Long id) {
        PartyFileKodSourceDO source = partyFileKodSourceMapper.selectById(id);
        if (source == null) {
            throw exception(PARTY_FILE_KOD_SOURCE_NOT_FOUND);
        }
        return source;
    }

    private void clearDefaultFlag() {
        PartyFileKodSourceDO defaultSource = partyFileKodSourceMapper.selectDefault();
        if (defaultSource == null) {
            return;
        }
        defaultSource.setIsDefault(false);
        partyFileKodSourceMapper.updateById(defaultSource);
    }

    private String normalizeBaseUrl(String baseUrl) {
        return StrUtil.addSuffixIfNot(StrUtil.trim(baseUrl), "/");
    }

    private String normalizeFolderPath(String path) {
        String normalized = StrUtil.trim(path);
        if (StrUtil.isBlank(normalized)) {
            throw exception(PARTY_FILE_KOD_FOLDER_PATH_INVALID);
        }
        return normalized;
    }
}
