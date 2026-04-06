CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    cognito_sub VARCHAR(255) UNIQUE NOT NULL,
    email VARCHAR(255) NOT NULL,
    name VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE profiles (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parsed_data JSONB DEFAULT '{}',
    skills TEXT[],
    headline VARCHAR(500),
    preferences JSONB DEFAULT '{}',
    resume_s3_key VARCHAR(500),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE jobs (
    id BIGSERIAL PRIMARY KEY,
    title VARCHAR(500) NOT NULL,
    company VARCHAR(500),
    location VARCHAR(500),
    source VARCHAR(50) NOT NULL,
    url TEXT,
    description TEXT,
    dedup_hash VARCHAR(64) UNIQUE NOT NULL,
    discovered_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE matches (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    job_id BIGINT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    keyword_score DOUBLE PRECISION,
    embedding_score DOUBLE PRECISION,
    llm_score DOUBLE PRECISION,
    final_score DOUBLE PRECISION,
    reasoning TEXT,
    status VARCHAR(20) DEFAULT 'new',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, job_id)
);

CREATE TABLE tailored_resumes (
    id BIGSERIAL PRIMARY KEY,
    match_id BIGINT UNIQUE NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    s3_key VARCHAR(500) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE schedules (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    cron_expression VARCHAR(100) NOT NULL,
    active BOOLEAN DEFAULT TRUE,
    last_run TIMESTAMP WITH TIME ZONE,
    next_run TIMESTAMP WITH TIME ZONE
);

CREATE TABLE notifications (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL,
    payload JSONB DEFAULT '{}',
    read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_matches_user_id ON matches(user_id);
CREATE INDEX idx_matches_final_score ON matches(final_score DESC);
CREATE INDEX idx_jobs_dedup_hash ON jobs(dedup_hash);
CREATE INDEX idx_notifications_user_id ON notifications(user_id);
