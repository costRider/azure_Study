#실행 방법 (예: PowerShell/CMD/WSL 공통)
### 리소스 그룹
az group create -n rg-hubspoke-demo -l koreacentral

### 배포 (adminPassword는 임시 값; 운영은 Key Vault 참조 권장)
```
az deployment group create \
  -g rg-hubspoke-demo \
  -f hub-spoke-arm-bicep-main.bicep \
  -p adminUsername=mklee adminPassword='P@ssw0rd!' namePrefix=test
```

다음에 맞춤화할 수 있는 부분

VPN 연결(Connection/Local Network Gateway): 실제 온프렘/상대 VNet 정보 넣어서 S2S 구성 추가.

NSG 규칙: 포트/원천 대역 조정.

Traffic Manager: Performance/Weighted 등 라우팅 방식 변경, 헬스체크 경로 /health로 조정.

Private DNS Zone: Spoke들에도 링크 추가(허브만 연결해둠 → 필요 시 spoke A/B 링크 추가).

이미지/OS: Windows Server 2022 -> 원하는 이미지로 교체.

모듈로 분리: 네트워크/보안/컴퓨트/글로벌(Traffic Manager)로 쪼개서 Template Specs 등록.