CREATE TABLE IF NOT EXISTS users (
  id serial PRIMARY KEY,
  name varchar(100) NOT NULL,
  email varchar(200) UNIQUE NOT NULL
);
