-- Showtimes query
-- Set @search_city and @show_date before running.
-- DATETIME values are stored as UTC. The date parameter is interpreted
-- in the same timezone policy used by the application.
SET @search_city = 'Ghaziabad';
SET @show_date = '2026-12-01';

SET @day_start = CAST(CONCAT(@show_date, ' 00:00:00') AS DATETIME);
SET @day_end = DATE_ADD(@day_start, INTERVAL 1 DAY);

SELECT
    sh.show_id,
    m.movie_title,
    m.language,
    m.duration_minutes,
    m.certification,
    t.theatre_name,
    t.city,
    a.auditorium_name,
    sh.start_time,
    sh.end_time,
    sh.base_price,
    sh.currency
FROM `SHOW` AS sh
JOIN MOVIE AS m
    ON m.movie_id = sh.movie_id
JOIN AUDITORIUM AS a
    ON a.auditorium_id = sh.auditorium_id
JOIN THEATRE AS t
    ON t.theatre_id = a.theatre_id
WHERE t.city = (@search_city COLLATE utf8mb4_0900_as_ci)
  AND sh.start_time >= @day_start
  AND sh.start_time < @day_end
  AND sh.status = 'SCHEDULED'
ORDER BY sh.start_time, t.theatre_name, a.auditorium_name;
