-- Schema bootstrap. Loaded by the Bitnami MySQL initdb hook (mounted from the
-- mysql-initdb ConfigMap) and by docker-compose. Bitnami runs initdb scripts
-- without an implicit database selected, so create + USE appdb explicitly —
-- otherwise the table can land in the wrong schema.
CREATE DATABASE IF NOT EXISTS appdb;
USE appdb;

CREATE TABLE IF NOT EXISTS items (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  name       VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT IGNORE INTO items (id, name) VALUES (1, 'seed-item-1'), (2, 'seed-item-2');
