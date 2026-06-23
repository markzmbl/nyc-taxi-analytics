"""Find Airbyte source/destination definition IDs matching keywords."""

from airbyte.airbyte_client import post

# Source definitions
print("=== SOURCE DEFINITIONS ===")
sd = post("/source_definitions/list")
for item in sd.get("sourceDefinitions", []):
    print(f"  {item['sourceDefinitionId']}  {item['name']}")

# Destination definitions
print("\n=== DESTINATION DEFINITIONS ===")
dd = post("/destination_definitions/list")
keywords = ["postgres", "postgre"]
for item in dd.get("destinationDefinitions", []):
    name = item.get("name", "").lower()
    if any(kw in name for kw in keywords):
        print(f"  {item['destinationDefinitionId']}  {item['name']}")
