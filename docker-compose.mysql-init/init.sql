CREATE DATABASE IF NOT EXISTS crm_development;
CREATE DATABASE IF NOT EXISTS crm_test;
GRANT ALL ON crm_development.* TO 'crm_app'@'%';
GRANT ALL ON crm_test.* TO 'crm_app'@'%';
FLUSH PRIVILEGES;
