package com.nutriflow.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;

import java.io.IOException;
import java.time.Duration;
import java.util.UUID;

/**
 * Handles file uploads to OSS (MinIO / Aliyun OSS) and generates pre-signed
 * download URLs for downstream AI analysis.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class OssService {

    private final S3Client s3Client;
    private final S3Presigner s3Presigner;

    @Value("${oss.bucket-name}")
    private String bucketName;

    /**
     * Uploads a meal image and returns its OSS object key.
     *
     * @param userId   the owning user
     * @param mealType e.g. LUNCH
     * @param file     the multipart image file
     * @return OSS key (relative path inside the bucket)
     */
    public String uploadMealImage(String userId, String mealType, MultipartFile file) throws IOException {
        String extension = extractExtension(file.getOriginalFilename());
        String ossKey = String.format("meals/%s/%s_%s.%s",
                userId, mealType.toLowerCase(), UUID.randomUUID(), extension);

        PutObjectRequest request = PutObjectRequest.builder()
                .bucket(bucketName)
                .key(ossKey)
                .contentType(file.getContentType())
                .build();

        s3Client.putObject(request, RequestBody.fromInputStream(file.getInputStream(), file.getSize()));
        log.info("Uploaded meal image: bucket={}, key={}", bucketName, ossKey);
        return ossKey;
    }

    /**
     * Generates a pre-signed GET URL valid for 1 hour.
     *
     * @param ossKey the object key
     * @return pre-signed URL string
     */
    public String generatePresignedUrl(String ossKey) {
        GetObjectPresignRequest presignRequest = GetObjectPresignRequest.builder()
                .signatureDuration(Duration.ofHours(1))
                .getObjectRequest(GetObjectRequest.builder()
                        .bucket(bucketName)
                        .key(ossKey)
                        .build())
                .build();

        return s3Presigner.presignGetObject(presignRequest).url().toString();
    }

    private String extractExtension(String filename) {
        if (filename == null || !filename.contains(".")) {
            return "jpg";
        }
        return filename.substring(filename.lastIndexOf('.') + 1).toLowerCase();
    }
}
