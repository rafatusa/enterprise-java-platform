-- Initial schema for the task domain.
CREATE TABLE tasks (
    id          BIGSERIAL PRIMARY KEY,
    title       VARCHAR(200)  NOT NULL,
    description VARCHAR(2000),
    status      VARCHAR(20)   NOT NULL DEFAULT 'OPEN',
    priority    INTEGER       NOT NULL DEFAULT 3,
    created_at  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_tasks_status
        CHECK (status IN ('OPEN', 'IN_PROGRESS', 'BLOCKED', 'DONE')),
    CONSTRAINT chk_tasks_priority
        CHECK (priority BETWEEN 1 AND 5)
);

-- Status filtering is the most common query path (GET /api/v1/tasks?status=...).
CREATE INDEX idx_tasks_status ON tasks (status);

-- Supports the /urgent endpoint.
CREATE INDEX idx_tasks_priority ON tasks (priority);
