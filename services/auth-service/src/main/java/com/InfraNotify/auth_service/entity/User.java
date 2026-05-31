package com.InfraNotify.auth_service.entity;

import java.time.Instant;
import java.util.UUID;

import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(
		name = "users",
		uniqueConstraints = {
				@UniqueConstraint(name = "uk_users_email", columnNames = "email"),
				@UniqueConstraint(name = "uk_users_provider_provider_id", columnNames = {"provider", "provider_id"})
		},
		indexes = {
				@Index(name = "idx_users_email", columnList = "email"),
				@Index(name = "idx_users_provider", columnList = "provider"),
				@Index(name = "idx_users_provider_id", columnList = "provider_id")
		}
)
public class User {

	@Id
	@GeneratedValue(strategy = GenerationType.UUID)
	@Column(name = "id", nullable = false, updatable = false)
	private UUID id;

	@Column(name = "email", nullable = false, length = 320)
	private String email;

	@Enumerated(EnumType.STRING)
	@Column(name = "provider", nullable = false, length = 50)
	private AuthProvider provider;

	@Column(name = "provider_id", length = 255)
	private String providerId;

	@Column(name = "password_hash", length = 255)
	private String passwordHash;

	@CreationTimestamp
	@Column(name = "created_at", nullable = false, updatable = false)
	private Instant createdAt;

	@UpdateTimestamp
	@Column(name = "updated_at", nullable = false)
	private Instant updatedAt;
}
