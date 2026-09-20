"""Generate synthetic app files in a supplied scratch directory, never a real app store.
Copy only into a dedicated QA simulator. Values are fictional, not historical data.
"""
import datetime as dt
import json
import pathlib
import sys
import uuid
from zoneinfo import ZoneInfo

out = pathlib.Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
now = dt.datetime.now(ZoneInfo('America/New_York')).replace(microsecond=0)
def iso(value): return value.astimezone(dt.timezone.utc).isoformat().replace('+00:00', 'Z')
def uid(): return str(uuid.uuid4()).upper()
profile = dict(id=uid(), name='Alex · Preview', relationship='myself', source='synthetic', medicalConditions=[], mentalConditions=[], medications=[], createdAt=iso(now), updatedAt=iso(now))
place = dict(name='Central Park', formattedAddress='Central Park, New York, NY', latitude=40.7829, longitude=-73.9654, timeZoneIdentifier='America/New_York')
events = []
for day in range(7):
    start = (now - dt.timedelta(days=day)).replace(hour=8, minute=0, second=0)
    end = start + dt.timedelta(hours=1.5)
    retrieved = start - dt.timedelta(hours=6)
    category = [42, 68, 110, 160, 48, 35, 80][day]
    samples = [dict(timestamp=iso(start + dt.timedelta(hours=h)), pm25=12 + day * 2, usAQI=category, apparentTemperatureC=23) for h in range(2)]
    series = dict(samples=samples, source='Synthetic visual QA fixture', kind='forecast', fetchedAt=iso(retrieved), timeZoneIdentifier='America/New_York', intervalSemantics='Hour starting at timestamp; fictional QA values.')
    plan = dict(id=uid(), profileID=profile['id'], activityType='exercise', activityName=['Morning walk', 'Park run', 'Tennis practice'][day % 3], location=place, startTime=iso(start), durationMinutes=90, constraints=dict(timeFlexibility='oneHour'))
    snapshot = dict(analyzedAt=iso(retrieved), source=series['source'], sourceUpdatedAt=iso(retrieved), originalStart=iso(start), selectedStart=iso(start), pm25Mean=12 + day * 2, apparentTemperatureC=23, environmentalWindow=dict(location=place, start=iso(start), end=iso(end), series=series))
    events.append(dict(id=uid(), plan=plan, selectedStart=iso(start), analysis=snapshot if day != 4 else None, source='Exposure Navigator', createdAt=iso(retrieved)))
# Upcoming plan exercises the normal edit/results flow with a public test location.
start = (now + dt.timedelta(hours=2)).replace(minute=0, second=0)
plan = dict(id=uid(), profileID=profile['id'], activityType='exercise', activityName='Afternoon walk', location=place, startTime=iso(start), durationMinutes=60, constraints=dict(timeFlexibility='oneHour'))
events.append(dict(id=uid(), plan=plan, selectedStart=iso(start), source='Exposure Navigator', createdAt=iso(now)))
(out / 'profiles-v2.json').write_text(json.dumps([profile]))
(out / 'events.json').write_text(json.dumps(events))
print(profile['id'])
