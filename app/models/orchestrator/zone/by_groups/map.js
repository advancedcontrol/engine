
function(doc) {
    if(doc.type == "zone") {
        var i;
        for (i = 0; i < doc.groups.length; i++) {
            emit(doc.groups[i], null);
        }
    }
}
