graph TD

%% ===========================
%% LAYER 1 — CCM (TOP)
%% ===========================
subgraph CCM["Collateral Contract Management"]
    direction TB
    
    CGW["Cloud Gateway / Presentation"]

    subgraph CCM_MS["CCM Microservices"]
        LVX["LVX Service"]
        TPP["TPP Service"]
        LOU["LOU Service"]
        PGC["PGCG Service"]
        PA["Pending Actions (Consumer Only)"]
    end
end


%% UI + Workbench + Proxies (still in top layer logically)


UserBrowser[User Browser]


subgraph WB["Workbench UI"]
        Workbench["JOA App"]
        BC5[BC5 Pending Actions]
        DWA[DWA Pending Actions]
end


UserBrowser --> Workbench
Workbench --> BC5
Workbench --> DWA

subgraph APIGEE["API Gateway - Apigee"]
    HAW["HAW Proxy (CCM)"]
    DI9["DI9 Proxy (GLP PAI)"]
end

BC5 --> HAW
DWA --> DI9

HAW --> CGW
CGW --> LVX
CGW --> TPP
CGW --> LOU
CGW --> PGC
CGW --> PA


%% ===========================
%% LAYER 2 — KAFKA CLUSTER (MIDDLE)
%% ===========================
subgraph KAFKA["Kafka Cluster"]
    direction LR
    topic041["PA Topic 041"]
    topic023["PA Topic 023"]
    topic036["PA Topic 036"]
    topic042["PA Topic 042"]
end


%% Publishers (CCM microservices)
LVX -.-> topic041
LVX -.-> topic023
LVX -.-> topic036
LVX -.-> topic042

TPP -.-> topic041
TPP -.-> topic023
TPP -.-> topic036
TPP -.-> topic042

LOU -.-> topic041
LOU -.-> topic023
LOU -.-> topic036
LOU -.-> topic042

PGC -.-> topic041
PGC -.-> topic023
PGC -.-> topic036
PGC -.-> topic042

%% CCM Consumer
topic041 e1@-.-> PA
topic023 e2@-.-> PA
topic036 e3@-.-> PA
topic042 e4@-.-> PA

e1@{ animate: true }
e2@{ animate: true }
e3@{ animate: true }
e4@{ animate: true }




%% ===========================
%% LAYER 3 — GLP PENDING ACTIONS (BOTTOM)
%% ===========================
subgraph GLP["GLP Pending Actions"]
    GLPPA["GLP Pending Actions Service"]
end

DI9 --> GLPPA

topic041 e11@-.-> GLPPA
topic023 e22@-.-> GLPPA
topic036 e33@-.-> GLPPA
topic042 e44@-.-> GLPPA

e11@{ animate: true }
e22@{ animate: true }
e33@{ animate: true }
e44@{ animate: true }
