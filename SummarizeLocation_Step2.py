##------------Looking up help for a processing algorithm
#import processing
#
#processing.algorithmHelp("qgis:joinbylocationsummary")
#
##for alg in QgsApplication.processingRegistry().algorithms():
##        print(alg.id(), "->", alg.displayName())
#
   
#--------------------------For Parks and Equity
import os
from pprint import pprint

#Set directory
wd = 'C:/Users/klau/Desktop/ParksEquity/SummarizeLocation/'

#------ADD DATA
### Create list of target shapefiles that you want to add summary to: TPL10MW

## INPUT
listTargetShapes = []
for item in os.listdir(wd + '/INPUT/FIXED/'):
    if item[-3:]=='shp':
        listTargetShapes.append(item)

print(listTargetShapes)

#Create dictionary
dictTargetShapes = {}

#Add dictionary of shapefiles
for shape in listTargetShapes:
    fileKey = shape.replace('TPL10MW_', '').replace('.shp', '')
    dictTargetShapes[fileKey] = iface.addVectorLayer(wd + '/INPUT/FIXED/' + shape,shape[:-4],"ogr")
pprint(dictTargetShapes)

#Turn off layers
for layer in dictTargetShapes.keys():
    QgsProject.instance().layerTreeRoot().findLayer(dictTargetShapes[layer]).setItemVisibilityChecked(False)
print("Target layers turned off")

### Add layers to summarize data from = Blocks

#JOIN: 
## If using just one shapefile
#overlay = iface.addVectorLayer(wd + '/QGIS_ScriptTestFiles/Difference/OVERLAY/Overlay1.shp' ,'Overlay',"ogr")

## For multiple shapefiles - List of Joins
listJoinShapes = []
for item in os.listdir(wd + '/JOIN/Merged/'):
    if item[-3:]=='shp':
        listJoinShapes.append(item)

print(listJoinShapes)

#Create dictionary
dictJoinShapes = {}

#Add dictionary of shapefiles
for shape in listJoinShapes:
    fileKey = shape.replace('.shp', '')
    dictJoinShapes[fileKey] = iface.addVectorLayer(wd + '/JOIN/Merged/' + shape,shape[:-4],"ogr")
pprint(dictJoinShapes)

#Turn off layers
for layer in dictJoinShapes.keys():
    QgsProject.instance().layerTreeRoot().findLayer(dictJoinShapes[layer]).setItemVisibilityChecked(False)
print("Join layers turned off")

#------First Join attributes by location (summary)
#INPUTS = TPL10MW
#OVERLAY = Blocks
import processing

for input in dictTargetShapes.keys():
    processing.run("qgis:joinbylocationsummary",\
            { 'DISCARD_NONMATCHING' : False,\
            'INPUT' : dictTargetShapes[input],\
            'JOIN' : dictJoinShapes[input],\
            'JOIN_FIELDS' : ['S_ratotpop'],\
            'OUTPUT' : wd+'/OUTPUT/'+input+'_J.shp',\
            'PREDICATE' : [0],\
            'SUMMARIES' : [5] })
    print("{} join attribute by location done".format(input))
    #iface.addVectorLayer(wd+'/OUTPUT/Test'+input+'_Attjoin.shp','Test'+input+'_Attjoin',"ogr")
    #print("{}_Attjoin added to map".format(input))

###-------Add PrcAcs to targets: Area/pop_sum
## Add in output from last step
listTargetShapes = []
for item in os.listdir(wd+'/OUTPUT/'):
    if item[-3:]=='shp':
        listTargetShapes.append(item)

print(listTargetShapes)

#Create dictionary
dictTargetShapes = {}

#Add dictionary of shapefiles
for shape in listTargetShapes:
    fileKey = shape.replace('_J.shp', '')
    dictTargetShapes[fileKey] = iface.addVectorLayer(wd + '/OUTPUT/' + shape,shape[:-4],"ogr")
pprint(dictTargetShapes)

#Turn off layers
for layer in dictTargetShapes.keys():
    QgsProject.instance().layerTreeRoot().findLayer(dictTargetShapes[layer]).setItemVisibilityChecked(False)
print("Target layers turned off")

## Create new field for Park Access
NewFields = {}
NewFields['PrkAcs'] = QgsField('PrkAcs', QVariant.Double, len=10,prec=3)

for layer in dictTargetShapes.keys():
    dictTargetShapes[layer].startEditing()
    for field in NewFields.keys():
        dictTargetShapes[layer].dataProvider().addAttributes([NewFields[field]])
        print(f'{layer}: {field} added')
    dictTargetShapes[layer].commitChanges()


## Delete field if needed
#
#for layer in dictTargetShapes.keys():
#    dictTargetShapes[layer].startEditing()
#    dictTargetShapes[layer].dataProvider().deleteAttributes([60])
#    print(f'{layer}: PrkAcs deleted')
#    dictTargetShapes[layer].commitChanges()

## Delete features where population = null
for layer in dictTargetShapes.keys():
    with edit(dictTargetShapes[layer]):
        # build a request to filter the features based on an attribute
        request = QgsFeatureRequest().setFilterExpression('"S_ratotpop" IS NULL')
        
        # we don't need attributes or geometry, skip them to minimize overhead.
        # these lines are not strictly required but improve performance
        request.setSubsetOfAttributes([])
        request.setFlags(QgsFeatureRequest.NoGeometry)
        
        # loop over the features and delete
        for f in dictTargetShapes[layer].getFeatures(request):
            dictTargetShapes[layer].deleteFeature(f.id())
    print(f"{layer}: Features deleted")

print("All done")
    
##Edit new field: PrkAcs
target_field = 'PrkAcs'

def calculate_prkacs(mainlayer):
    with edit(mainlayer):
        for feature in mainlayer.getFeatures():
            feature.setAttribute(feature.fieldNameIndex('PrkAcs'), feature['Acres']/feature['S_ratotpop'])
            mainlayer.updateFeature(feature)

for layer in dictTargetShapes.keys():
    QgsFeatureRequest().setSubsetOfAttributes([])
    QgsFeatureRequest().setFlags(QgsFeatureRequest.NoGeometry)
    calculate_prkacs(dictTargetShapes[layer])
    print(f'{layer}: {target_field} field calculated')

#-------Second Join attributes by location (summary)
#INPUTS = Blocks
#OVERLAY = TPL10MW

import processing

for input in dictTargetShapes.keys():
    processing.run("qgis:joinbylocationsummary",\
            { 'DISCARD_NONMATCHING' : False,\
            'INPUT' : dictJoinShapes[input],\
            'JOIN' : dictTargetShapes[input],\
            'JOIN_FIELDS' : ['PrkAcs'],\
            'OUTPUT' : wd+'/OUTPUT/FINALJOIN/'+input+'_J2.shp',\
            'PREDICATE' : [0],\
            'SUMMARIES' : [5] })
    print("{} join attribute by location done".format(input))
#    iface.addVectorLayer(wd+'/OUTPUT/Blk/Blk'+input+'_Attjoin.shp','Blk'+input+'_Attjoin',"ogr")
#    print("Blk{}_Attjoin added to map".format(input))