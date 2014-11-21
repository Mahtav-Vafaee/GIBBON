function [F,V]=regionTriMesh2D(regionCell,pointSpacing,resampleCurveOpt,plotOn)

% function [F,V]=regionTriMesh2D(regionCell,pointSpacing,plotOn)
% ------------------------------------------------------------------------
% This function creates a 2D triangulation for the region specified in the
% variable regionCell. The mesh aims to obtain a point spacing as defined
% by the input pointSpacing.
% The function output contains the triangular faces in F, the vertices in V
% and the per triangle region indices in regionInd. By setting plotOn to 0
% or 1 plotting can be switched on or off.
%
% More on the specification of the region:
% The input variable regionCell is a cell array containing all the boundary
% curves, e.g. for a two curve region 1 we would have something like
% regionSpec{1}={V1,V2} where V1 and V2 are the boundary curves. Multiple
% curves may be given here. The first curve should form the outer boundary
% of the entire region, the curves that follow should define holes inside
% this boundary and the space inside them is therefore not meshed.
%
% Kevin Mattheus Moerman
% kevinmoerman@hotmail.com
% 2013/14/08
%------------------------------------------------------------------------

%% CONTROL PARAMETERS
interpMethod='linear';
closeLoopOpt=1;
minConnectivity=4; %Minimum connectivity for points

%% PLOT SETTINGS
if plotOn==1;
    figColor='w'; figColorDef='white';
    fontSize=20;
    fAlpha=1;
    markerSize=20;
    faceColor='r';
end

%% Get region curves and define constraints for Delaunay tesselation

V=[]; %Curve points
VS=[]; %Curve points
C=[]; %Constraints
nss=0; %Number of points parameter for constraint index correction
for qCurve=1:1:numel(regionCell)
    %Get curve
    Vs=regionCell{qCurve};
    
    %Calculate required number of points for curve
    np=ceil(max(pathLength(Vs))./pointSpacing);
    [Vss]=evenlySampleCurve(Vs,np,interpMethod,closeLoopOpt);
    
    %Resample curve
    if resampleCurveOpt==1
       Vs=Vss;
    end
    
    %Collect curve points
    V=[V;Vs]; %Original or interpolated set
    
    VS=[V;Vss]; %Interpolated set
    
    %Create curve constrains
    ns= size(Vs,1);
    Cs=[(1:ns)' [2:ns 1]'];
    C=[C;Cs+nss];
    nss=nss+ns;
end

%% DEFINE INTERNAL MESH SEED POINTS

methodOpt=2; 

%region extrema
maxVi=max(V(:,[1 2]),[],1);
minVi=min(V(:,[1 2]),[],1);

switch methodOpt
    case 1 %Aproximate regular triangles but more symmetric
        %Mesh point spacing for aproximately equilateral triangular mesh
        pointSpacingXY=[pointSpacing pointSpacing.*0.5.*sqrt(3)];
        
        maxV=maxVi+pointSpacingXY;
        minV=minVi-pointSpacingXY;
        
        %Region "Field Of View" size
        FOV=abs(maxV-minV);
        
        %Calculate number of points in each direction
        FOV_dev=FOV./pointSpacingXY;
        
        npXY=round(FOV_dev);
        
        %Get mesh of seed points
        xRange=linspace(minV(1),maxV(1),npXY(1));
        yRange=linspace(minV(2),maxV(2),npXY(2));
        [X,Y]=meshgrid(xRange,yRange);
        
        %Offset mesh in X direction to obtain aproximate equilateral triangular mesh
        X(1:2:end,:)=X(1:2:end,:)+(pointSpacing/2);
        
    case 2 %Close to regular triangles but possibly assymetric
        [~,Vt]=triMeshEquilateral(minVi,maxVi,pointSpacing);
        X=Vt(:,1); Y=Vt(:,2);
end

X=X(:); 
Y=Y(:);

%%

[VSS]=subCurve(VS,2); %Point spacing is aproximately pointSpacing/3

[D,~]=minDist([X Y],VSS); 
L=D>(pointSpacing*0.5*sqrt(3))/2;

X=X(L);
Y=Y(L);

%%
%Adding seed points to list
V_add=[X(:) Y(:)];

V=[V;V_add]; %Total point set of curves and seeds
numPointsIni=size(V,1);

%% DERIVE CONSTRAINED DELAUNAY TESSELATION

%Initial Delaunay triangulation
DT = delaunayTriangulation(V(:,1),V(:,2),C);
V=DT.Points;
F=DT.ConnectivityList;

%Remove poorly connected points associated with poor triangles
[~,IND_V]=patchIND(F,V);
connectivityCount=sum(IND_V>0,2);
logicPoorConnectivity=connectivityCount<=minConnectivity;
logicConstraints=false(size(logicPoorConnectivity));
logicConstraints(C(:))=1;
logicRemoveList=logicPoorConnectivity & ~logicConstraints;
logicKeepList=~logicRemoveList;
V=V(logicKeepList,:); %Remove points
numPoints=size(V,1);

%Fix constraints list
indNew=(1:numPoints)';
indFix=zeros(numPointsIni,1);
indFix(logicKeepList)=indNew;
C=indFix(C);

%Redo Delaunary triangulation
DT = delaunayTriangulation(V(:,1),V(:,2),C);
V=DT.Points;
F=DT.ConnectivityList;

%Remove faces not inside region
L = isInterior(DT);
F=F(L,:);

%Removing unused points
indUni=unique(F(:));
indNew=nan(size(V,1),1);
indNew(indUni)=(1:numel(indUni))';
F=indNew(F);
V=V(indUni,:);

numPointsPost=size(V,1);

if numPoints==numPointsPost
    warning('No points removed in contrained Delaunay triangulation. Possibly due to large pointSpacing with respect to curve size. Meshing skipped!');
    F=[];
    V=[];
else
    
    %% CONSTRAINED SMOOTHENING OF THE MESH
    
    TR = triangulation(F,V);
    boundEdges = freeBoundary(TR);
    boundaryInd=unique(boundEdges(:));
    
    smoothPar.LambdaSmooth=0.5;
    smoothPar.n=250;
    smoothPar.Tolerance=0.01;
    smoothPar.RigidConstraints=boundaryInd;
    [V]=tesSmooth(F,V,[],smoothPar);    
    
    %% PLOTTING
    if plotOn==1
        figuremax(figColor,figColorDef);
        title('The meshed model','FontSize',fontSize);
        xlabel('X','FontSize',fontSize);ylabel('Y','FontSize',fontSize);zlabel('Z','FontSize',fontSize);
        hold on;
        patch('faces',F,'vertices',V,'FaceColor',faceColor,'FaceAlpha',fAlpha);
        plotV(V(boundaryInd',:),'b.','MarkerSize',markerSize);
%         plot(X,Y,'k.','MarkerSize',markerSize);
        axis equal; view(2); axis tight;  set(gca,'FontSize',fontSize); grid on;
        drawnow;
    end
    
end