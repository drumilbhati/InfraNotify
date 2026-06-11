CREATE TABLE monitored_services (
    id UUID PRIMARY KEY,
    owner_id UUID NOT NULL,
    endpoint_url VARCHAR(2083) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT fk_monitored_services_owner_id FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_monitored_services_owner_id ON monitored_services (owner_id);
CREATE INDEX idx_monitored_services_is_active ON monitored_services (is_active);
