# Constants
current_block = 18860353
target_block = 4294967295 # uint32
# target_block = 65535 # uint16
block_time = 10

# Calculate time in seconds
time_seconds = (target_block - current_block) * block_time

# Convert time to days, months, and years
time_days = time_seconds / (24 * 60 * 60)  # 1 day = 24 hours * 60 minutes * 60 seconds
time_months = time_days / 30.44  # Assuming an average month length of 30.44 days
time_years = time_days / 365.25  # Assuming a year of 365.25 days to account for leap years

print("input current_block:", current_block)
print("input target_block:", target_block)
print("input current_block:", block_time)
print(" Time in seconds:", time_seconds)
print(" Time in days:", time_days)
print(" Time in months:", time_months)
print(" Time in years:", time_years)
