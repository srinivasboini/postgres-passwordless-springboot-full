package com.example.azure.config;

import com.azure.core.credential.AccessToken;
import com.azure.core.credential.TokenCredential;
import com.azure.core.credential.TokenRequestContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import reactor.core.publisher.Mono;

import java.time.OffsetDateTime;

/**
 * Configuration for debugging Azure token authentication.
 * Enable this by setting: azure.token.debug.enabled=true
 * Set custom token expiry: azure.token.debug.expiry-minutes=2
 */
@Configuration
@ConditionalOnProperty(name = "azure.token.debug.enabled", havingValue = "true")
public class TokenDebugConfiguration {

    private static final Logger log = LoggerFactory.getLogger(TokenDebugConfiguration.class);

    @Value("${azure.token.debug.expiry-minutes:2}")
    private int tokenExpiryMinutes;

    @Bean
    public TokenDebugInterceptor tokenDebugInterceptor() {
        log.warn("========================================");
        log.warn("TOKEN DEBUG MODE ENABLED");
        log.warn("Token expiry override: {} minutes", tokenExpiryMinutes);
        log.warn("DO NOT USE IN PRODUCTION!");
        log.warn("========================================");
        return new TokenDebugInterceptor(tokenExpiryMinutes);
    }

    public static class TokenDebugInterceptor {
        private static final Logger log = LoggerFactory.getLogger(TokenDebugInterceptor.class);
        private final int expiryMinutes;

        public TokenDebugInterceptor(int expiryMinutes) {
            this.expiryMinutes = expiryMinutes;
        }

        /**
         * Wraps a TokenCredential to override token expiry time for testing.
         * This allows testing token refresh behavior without waiting for actual expiry.
         */
        public TokenCredential wrapCredential(TokenCredential originalCredential) {
            return new TokenCredential() {
                @Override
                public Mono<AccessToken> getToken(TokenRequestContext request) {
                    log.info("🔐 TOKEN REQUEST START");
                    log.info("  Scopes: {}", request.getScopes());
                    log.info("  Claims: {}", request.getClaims());

                    return originalCredential.getToken(request)
                        .doOnSuccess(token -> {
                            OffsetDateTime originalExpiry = token.getExpiresAt();
                            OffsetDateTime customExpiry = OffsetDateTime.now().plusMinutes(expiryMinutes);

                            log.info("✅ TOKEN ACQUIRED");
                            log.info("  Original Expiry: {}", originalExpiry);
                            log.info("  Custom Expiry: {} ({} minutes)", customExpiry, expiryMinutes);
                            log.info("  Token (first 10 chars): {}...",
                                token.getToken().substring(0, Math.min(10, token.getToken().length())));
                        })
                        .doOnError(error -> {
                            log.error("❌ TOKEN ACQUISITION FAILED", error);
                        })
                        .map(token -> {
                            // Override the expiry time for testing
                            OffsetDateTime customExpiry = OffsetDateTime.now().plusMinutes(expiryMinutes);
                            return new AccessToken(token.getToken(), customExpiry);
                        });
                }
            };
        }

        public void logTokenRefresh(String context) {
            log.info("🔄 TOKEN REFRESH triggered from: {}", context);
        }
    }
}
