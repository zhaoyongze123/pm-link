package cn.iocoder.yudao.module.system.service.partyfile;

import cn.hutool.core.date.DateUtil;
import cn.hutool.core.util.IdUtil;
import cn.hutool.core.util.StrUtil;
import cn.hutool.http.HttpRequest;
import cn.hutool.http.HttpResponse;
import cn.iocoder.yudao.framework.common.exception.ServiceException;
import cn.iocoder.yudao.framework.common.util.http.HttpUtils;
import cn.iocoder.yudao.framework.common.util.json.JsonUtils;
import cn.iocoder.yudao.framework.common.util.object.BeanUtils;
import cn.iocoder.yudao.module.infra.controller.admin.file.vo.file.FileCreateReqVO;
import cn.iocoder.yudao.module.infra.dal.dataobject.file.FileDO;
import cn.iocoder.yudao.module.infra.framework.file.core.utils.FileTypeUtils;
import cn.iocoder.yudao.module.infra.dal.mysql.file.FileMapper;
import cn.iocoder.yudao.module.infra.framework.file.core.client.FileClient;
import cn.iocoder.yudao.module.infra.service.file.FileConfigService;
import cn.iocoder.yudao.module.infra.service.file.FileService;
import cn.iocoder.yudao.module.system.controller.admin.partyfile.vo.file.PartyFileAttachmentUploadRespVO;
import cn.iocoder.yudao.module.system.controller.admin.partyfile.vo.file.PartyFileKodFileRespVO;
import cn.iocoder.yudao.module.system.controller.admin.partyfile.vo.file.PartyFileKodSelectFileReqVO;
import cn.iocoder.yudao.module.system.controller.admin.partyfile.vo.file.PartyFileKodSelectReqVO;
import cn.iocoder.yudao.module.system.dal.dataobject.partyfile.PartyFileKodAttachmentDO;
import cn.iocoder.yudao.module.system.dal.dataobject.partyfile.PartyFileKodSourceDO;
import cn.iocoder.yudao.module.system.dal.mysql.partyfile.PartyFileKodAttachmentMapper;
import cn.iocoder.yudao.module.system.enums.partyfile.PartyFileStorageTypeEnum;
import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.stereotype.Service;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.multipart.MultipartFile;

import javax.annotation.Resource;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

import static cn.iocoder.yudao.framework.common.exception.util.ServiceExceptionUtil.exception;
import static cn.iocoder.yudao.module.system.enums.ErrorCodeConstants.PARTY_FILE_ATTACHMENT_NOT_FOUND;
import static cn.iocoder.yudao.module.system.enums.ErrorCodeConstants.PARTY_FILE_KOD_REQUEST_FAILED;
import static cn.iocoder.yudao.module.system.enums.ErrorCodeConstants.PARTY_FILE_STORAGE_CONFIG_INVALID;

@Service
@Validated
public class PartyFileAttachmentServiceImpl implements PartyFileAttachmentService {

    @Resource
    private FileService fileService;
    @Resource
    private FileMapper fileMapper;
    @Resource
    private FileConfigService fileConfigService;
    @Resource
    private PartyFileKodSourceServiceImpl partyFileKodSourceService;
    @Resource
    private PartyFileKodAttachmentMapper partyFileKodAttachmentMapper;

    @Override
    public PartyFileAttachmentUploadRespVO uploadAttachment(MultipartFile file, Integer storageType, Long kodSourceId,
                                                            String kodFolderPath) throws Exception {
        if (file == null || file.isEmpty()) {
            throw exception(PARTY_FILE_ATTACHMENT_NOT_FOUND);
        }
        if (PartyFileStorageTypeEnum.isKod(storageType)) {
            return uploadKodAttachment(file, kodSourceId, kodFolderPath);
        }
        return uploadLocalAttachment(file);
    }

    @Override
    public List<PartyFileKodFileRespVO> getKodFiles(Long kodSourceId, String kodFolderPath) {
        if (kodSourceId == null || StrUtil.isBlank(kodFolderPath)) {
            throw exception(PARTY_FILE_STORAGE_CONFIG_INVALID);
        }
        PartyFileKodSourceDO source = partyFileKodSourceService.getEnabledSource(kodSourceId);
        JsonNode current = partyFileKodSourceService.requestKodFolderList(source, kodFolderPath);
        JsonNode fileList = current.path("fileList");
        if (!fileList.isArray() || fileList.isEmpty()) {
            return new ArrayList<>();
        }
        List<PartyFileKodFileRespVO> result = new ArrayList<>();
        for (JsonNode fileNode : fileList) {
            PartyFileKodFileRespVO file = new PartyFileKodFileRespVO();
            file.setName(firstNonBlank(fileNode, null, "name"));
            file.setPath(firstNonBlank(fileNode, null, "path"));
            file.setPathDisplay(firstNonBlank(fileNode, null, "pathDisplay"));
            file.setSize(fileNode.has("size") ? fileNode.path("size").asLong(0L) : 0L);
            file.setType(FileTypeUtils.getMineType(file.getName()));
            if (StrUtil.isBlank(file.getName()) || StrUtil.isBlank(file.getPath())) {
                continue;
            }
            result.add(file);
        }
        return result;
    }

    @Override
    public List<PartyFileAttachmentUploadRespVO> selectKodFiles(PartyFileKodSelectReqVO reqVO) {
        if (reqVO.getKodSourceId() == null || StrUtil.isBlank(reqVO.getKodFolderPath())) {
            throw exception(PARTY_FILE_STORAGE_CONFIG_INVALID);
        }
        partyFileKodSourceService.getEnabledSource(reqVO.getKodSourceId());
        List<PartyFileAttachmentUploadRespVO> result = new ArrayList<>();
        for (PartyFileKodSelectFileReqVO file : reqVO.getFiles()) {
            result.add(bindKodAttachment(reqVO.getKodSourceId(), reqVO.getKodFolderPath(), file));
        }
        return result;
    }

    @Override
    public FileDO getFile(Long fileId) {
        return fileMapper.selectById(fileId);
    }

    @Override
    public byte[] getAttachmentContent(Long fileId) throws Exception {
        FileDO file = fileMapper.selectById(fileId);
        if (file == null) {
            throw exception(PARTY_FILE_ATTACHMENT_NOT_FOUND);
        }
        PartyFileKodAttachmentDO kodAttachment = partyFileKodAttachmentMapper.selectByFileId(fileId);
        if (kodAttachment == null) {
            return fileService.getFileContent(file.getConfigId(), file.getPath());
        }
        PartyFileKodSourceDO source = partyFileKodSourceService.getEnabledSource(kodAttachment.getKodSourceId());
        return partyFileKodSourceService.executeWithValidAccessToken(source, accessToken -> readKodFile(source,
                accessToken, kodAttachment.getKodFilePath()));
    }

    private PartyFileAttachmentUploadRespVO uploadLocalAttachment(MultipartFile file) throws Exception {
        byte[] content = file.getBytes();
        FileClient client = fileConfigService.getMasterFileClient();
        String path = buildLocalPath(file.getOriginalFilename());
        String url = client.upload(content, path, file.getContentType());
        FileCreateReqVO createReqVO = new FileCreateReqVO();
        createReqVO.setConfigId(client.getId());
        createReqVO.setPath(path);
        createReqVO.setName(file.getOriginalFilename());
        createReqVO.setUrl(url);
        createReqVO.setType(file.getContentType());
        createReqVO.setSize(file.getSize());
        Long fileId = fileService.createFile(createReqVO);
        return buildUploadResp(fileId, file.getOriginalFilename(), url, file.getSize(), file.getContentType());
    }

    private PartyFileAttachmentUploadRespVO uploadKodAttachment(MultipartFile file, Long kodSourceId, String kodFolderPath) throws Exception {
        if (kodSourceId == null || StrUtil.isBlank(kodFolderPath)) {
            throw exception(PARTY_FILE_STORAGE_CONFIG_INVALID);
        }
        PartyFileKodSourceDO source = partyFileKodSourceService.getEnabledSource(kodSourceId);
        String folderPath = StrUtil.trim(kodFolderPath);
        String targetPath = StrUtil.addSuffixIfNot(folderPath, "/") + buildKodFileName(file.getOriginalFilename());
        JsonNode fileInfo = partyFileKodSourceService.executeWithValidAccessToken(source,
                accessToken -> uploadKodFile(source, accessToken, folderPath, file));
        String actualFilePath = firstNonBlank(fileInfo, targetPath, "path", "pathDisplay", "downloadPath");
        if (StrUtil.isBlank(actualFilePath)) {
            actualFilePath = targetPath;
        }
        return createKodAttachment(kodSourceId, folderPath, actualFilePath, file.getOriginalFilename(),
                file.getSize(), file.getContentType());
    }

    private PartyFileAttachmentUploadRespVO buildUploadResp(Long fileId, String name, String url, Long size, String type) {
        PartyFileAttachmentUploadRespVO respVO = new PartyFileAttachmentUploadRespVO();
        respVO.setId(fileId);
        respVO.setName(name);
        respVO.setUrl(url);
        respVO.setSize(size);
        respVO.setType(type);
        return respVO;
    }

    private String buildLocalPath(String originalFilename) {
        String ext = StrUtil.subAfter(originalFilename, ".", true);
        String suffix = StrUtil.isBlank(ext) ? "" : "." + ext;
        return "party-file/" + DateUtil.today() + "/" + IdUtil.fastSimpleUUID() + suffix;
    }

    private String buildKodFileName(String originalFilename) {
        String ext = StrUtil.subAfter(originalFilename, ".", true);
        String suffix = StrUtil.isBlank(ext) ? "" : "." + ext;
        return DateUtil.formatDateTime(DateUtil.date()).replaceAll("[^0-9]", "")
                + "_" + IdUtil.fastSimpleUUID() + suffix;
    }

    private PartyFileAttachmentUploadRespVO bindKodAttachment(Long kodSourceId, String kodFolderPath,
                                                              PartyFileKodSelectFileReqVO file) {
        String fileType = StrUtil.blankToDefault(file.getType(), FileTypeUtils.getMineType(file.getName()));
        return createKodAttachment(kodSourceId, StrUtil.trim(kodFolderPath), StrUtil.trim(file.getPath()),
                file.getName(), file.getSize(), fileType);
    }

    private PartyFileAttachmentUploadRespVO createKodAttachment(Long kodSourceId, String parentPath, String filePath,
                                                                String fileName, Long fileSize, String fileType) {
        FileClient client = fileConfigService.getMasterFileClient();
        String virtualUrl = "kod://" + kodSourceId + "/" + IdUtil.fastSimpleUUID();
        FileCreateReqVO createReqVO = new FileCreateReqVO();
        createReqVO.setConfigId(client.getId());
        createReqVO.setPath("kod/" + kodSourceId + "/" + IdUtil.fastSimpleUUID());
        createReqVO.setName(fileName);
        createReqVO.setUrl(virtualUrl);
        createReqVO.setType(fileType);
        createReqVO.setSize(fileSize);
        Long fileId = fileService.createFile(createReqVO);

        PartyFileKodAttachmentDO attachmentDO = new PartyFileKodAttachmentDO();
        attachmentDO.setFileId(fileId);
        attachmentDO.setKodSourceId(kodSourceId);
        attachmentDO.setKodParentPath(parentPath);
        attachmentDO.setKodFilePath(filePath);
        partyFileKodAttachmentMapper.insert(attachmentDO);
        return buildUploadResp(fileId, fileName, virtualUrl, fileSize, fileType);
    }

    private String firstNonBlank(JsonNode node, String defaultValue, String... keys) {
        if (node != null && node.isObject()) {
            for (String key : keys) {
                JsonNode value = node.get(key);
                if (value != null && !value.isNull() && StrUtil.isNotBlank(value.asText())) {
                    return value.asText();
                }
            }
        }
        return defaultValue;
    }

    private byte[] readKodFile(PartyFileKodSourceDO source, String accessToken, String filePath) {
        String url = source.getBaseUrl()
                + "?explorer/index/fileOut&accessToken=" + HttpUtils.encodeUtf8(accessToken)
                + "&path=" + HttpUtils.encodeUtf8(filePath);
        try (HttpResponse response = HttpRequest.get(url).execute()) {
            if (response.getStatus() >= 400) {
                throw exception(PARTY_FILE_KOD_REQUEST_FAILED, "读取文件失败，HTTP " + response.getStatus());
            }
            String contentType = StrUtil.blankToDefault(response.header("Content-Type"), "");
            if (StrUtil.containsIgnoreCase(contentType, "application/json")) {
                JsonNode root = JsonUtils.parseTree(response.body());
                String message = extractKodMessage(root);
                if (partyFileKodSourceService.isKodAuthFailure(message)) {
                    throw exception(PARTY_FILE_KOD_REQUEST_FAILED, message);
                }
                throw exception(PARTY_FILE_KOD_REQUEST_FAILED, StrUtil.blankToDefault(message, "读取文件失败"));
            }
            return response.bodyBytes();
        } catch (ServiceException ex) {
            throw ex;
        } catch (Exception ex) {
            throw exception(PARTY_FILE_KOD_REQUEST_FAILED, ex.getMessage());
        }
    }

    private JsonNode uploadKodFile(PartyFileKodSourceDO source, String accessToken, String folderPath,
                                   MultipartFile file) throws Exception {
        String url = source.getBaseUrl() + "?explorer/upload/fileUpload"
                + "&accessToken=" + HttpUtils.encodeUtf8(accessToken)
                + "&path=" + HttpUtils.encodeUtf8(folderPath)
                + "&fileInfo=1";
        try (HttpResponse response = HttpRequest.post(url)
                .form("file", file.getBytes(), file.getOriginalFilename())
                .execute()) {
            if (response.getStatus() >= 400) {
                throw exception(PARTY_FILE_KOD_REQUEST_FAILED, "上传失败，HTTP " + response.getStatus());
            }
            JsonNode root = JsonUtils.parseTree(response.body());
            if (root == null || root.isMissingNode()) {
                throw exception(PARTY_FILE_KOD_REQUEST_FAILED, "上传返回为空");
            }
            String message = extractKodMessage(root);
            if (isKodFailure(root)) {
                throw exception(PARTY_FILE_KOD_REQUEST_FAILED, message);
            }
            if (root.has("info") && root.get("info").isObject()) {
                return root.get("info");
            }
            if (root.has("data") && root.get("data").isObject()) {
                return root.get("data");
            }
            return root;
        }
    }

    private boolean isKodFailure(JsonNode root) {
        if (root == null || root.isMissingNode()) {
            return true;
        }
        if (!root.has("code")) {
            return false;
        }
        JsonNode code = root.get("code");
        if (code.isBoolean()) {
            return !code.booleanValue();
        }
        String value = code.asText();
        return Objects.equals("10001", value) || "false".equalsIgnoreCase(value);
    }

    private String extractKodMessage(JsonNode root) {
        if (root == null || root.isMissingNode()) {
            return null;
        }
        for (String key : new String[]{"data", "msg", "message", "info"}) {
            JsonNode value = root.get(key);
            if (value != null && !value.isNull() && value.isValueNode() && StrUtil.isNotBlank(value.asText())) {
                return value.asText();
            }
        }
        return null;
    }
}
