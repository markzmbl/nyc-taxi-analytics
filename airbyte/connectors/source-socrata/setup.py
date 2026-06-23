from setuptools import find_packages, setup

setup(
    name="source-socrata",
    version="0.1.0",
    description="Airbyte source connector for Socrata Open Data API (generic, configurable per dataset)",
    author="Toph — Data Ingestion (Seeds & Bronze)",
    author_email="toph@nyc-taxi-analytics",
    url="https://data.cityofnewyork.us",
    packages=find_packages(),
    install_requires=[
        # 6.61.6 is the last 6.x release; it dropped the pendulum<3.0.0
        # dependency that prevented the 0.x/1.x series from building on
        # Python 3.12+. The Low-Code CDK YAML manifest API is unchanged.
        "airbyte-cdk>=6.0.0,<7.0.0",
    ],
    python_requires=">=3.11",
    entry_points={
        "console_scripts": [
            "source-socrata=source_socrata.source:SourceSocrata",
        ],
    },
    package_data={
        "source_socrata": ["manifest.yaml", "schemas/*.json"],
    },
    include_package_data=True,
)
