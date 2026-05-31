CREATE TABLE users (
    id UUID PRIMARY KEY,
    email VARCHAR(320) NOT NULL,
    provider VARCHAR(50) NOT NULL,
    provider_id VARCHAR(255),
    password_hash VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT uk_users_email UNIQUE (email),
    CONSTRAINT uk_users_provider_provider_id UNIQUE (provider, provider_id)
);

CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_users_provider ON users (provider);
CREATE INDEX idx_users_provider_id ON users (provider_id);
