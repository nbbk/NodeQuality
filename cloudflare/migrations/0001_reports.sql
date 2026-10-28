CREATE TABLE reports (id TEXT PRIMARY KEY, payload TEXT NOT NULL, delete_hash TEXT NOT NULL, created INTEGER NOT NULL, expires INTEGER NOT NULL);
CREATE INDEX report_expiry ON reports(expires);
CREATE TABLE uploads (created INTEGER NOT NULL);
CREATE INDEX upload_created ON uploads(created);
CREATE TRIGGER record_upload AFTER INSERT ON reports BEGIN
  INSERT INTO uploads(created) VALUES(NEW.created);
END;
